// pipeline minimal producer consumer framework that can be used to build
// the data pipeline with multiple stages. Pipeline is composed of Stage(s)
// Stage can be one of the 3 types:
//
//  1. Producer - produces the data
//  2. ProducerConsumer - intermediate stage in the pipeline that consumes the data from the producer
//     and produces the data for another consumer
//  3. Consumer - Consumes the data from the Producer or ProducerConsumer
//
// Each stage can have multiple workers running in parallel to speed up the data pipeline
// Number of workers for each Stage and how to segment the data has to be decided by the user
//
// Each stage is backed by a worker and a queue (buffered channel)
package pipeline

import (
	"errors"
	"fmt"
	"log"
	"slices"
	"sync"
	"time"
)

var DEFAULT_DEMAND_COUNT = 100

type Payload interface {
	Body() interface{}
}

type Stage interface {
	Identifier() string
	Init() error
	Start() error // TODO: check if this is really needed
}

type StageType string

var (
	StageTypeConsumer         StageType = "Consumer"
	StageTypeProducerConsumer StageType = "ProducerConsumer"
	StageTypeProducer         StageType = "Producer"
)

// StageConfig config for a given stage
type StageConfig struct {
	Type        StageType
	Identifier  string
	SubcribedTo []string // only applicable for stage type "Consumer"
}

type Producer interface {
	Stage
	HandleDemand(demandCount int) ([]Payload, error)
}

type Consumer interface {
	Stage
	HandleData(payload []Payload) error
}

type ProducerConsumer interface {
	Stage
	Producer
	Consumer
}

// Pipeline defines end-to-end export Pipeline
type Pipeline struct {
	done           chan struct{} // done channel to stop the pipeline
	Name           string
	stageMap       map[string]Stage
	stageConfigMap map[string]StageConfig
}

func (p *Pipeline) AddStage(s Stage, cfg StageConfig) error {
	if p.stageMap == nil {
		p.stageMap = make(map[string]Stage)
	}
	if p.stageConfigMap == nil {
		p.stageConfigMap = make(map[string]StageConfig)
	}

	if cfg.Type == StageTypeConsumer && cfg.SubcribedTo == nil || len(cfg.SubcribedTo) == 0 {
		return fmt.Errorf("%s not subscribed to any producer", cfg.Identifier)
	}

	// validate type
	switch cfg.Type {
	case StageTypeProducer:
		if _, ok := s.(Producer); !ok {
			return errors.New("invalid producer")
		}
	case StageTypeProducerConsumer:
		if _, ok := s.(ProducerConsumer); !ok {
			return errors.New("invalid producer consumer")
		}
	case StageTypeConsumer:
		if _, ok := s.(Consumer); !ok {
			return errors.New("invalid consumer")
		}
	}

	if _, ok := p.stageMap[cfg.Identifier]; ok {
		return fmt.Errorf("%s identifier already exists", cfg.Identifier)
	} else {
		p.stageMap[cfg.Identifier] = s
	}

	if _, ok := p.stageConfigMap[cfg.Identifier]; ok {
		return fmt.Errorf("%s identifier already exists", cfg.Identifier)
	} else {
		p.stageConfigMap[cfg.Identifier] = cfg
	}

	return nil
}

func (pipeline *Pipeline) Start() error {
	log.Println("Starting the pipeline...")

	pipeline.done = make(chan struct{})
	defer close(pipeline.done)

	for identifier, stage := range pipeline.stageMap {
		cfg := pipeline.stageConfigMap[identifier]
		if cfg.Type == StageTypeProducer {
			p, ok := stage.(Producer)
			if ok {
				pw := producerWorker{
					Producer:    p,
					BufferLimit: 5,
					WorkerCount: 1,
				}

				producerQueue, err := pw.Start(pipeline.done)
				if err != nil {
					return err
				}

				// find consumers for a producer above
				for _, consumerIdentifier := range pipeline.consumers(identifier) {
					stage := pipeline.stageMap[consumerIdentifier]
					cfg := pipeline.stageConfigMap[consumerIdentifier]

					if cfg.Type == StageTypeConsumer {
						c, ok := stage.(Consumer)
						if ok {
							cw := consumerWorker{
								Consumer: c,
							}
							cw.Start(pipeline.done, producerQueue)
						} else {
							return errors.New("consumer failed to start")
						}
					}
					if cfg.Type == StageTypeProducerConsumer {
						pc, ok := stage.(ProducerConsumer)
						if ok {
							pcw := producerConsumerWorker{
								producerConsumer: pc,
							}
							pcw.Start(pipeline.done, producerQueue)
						} else {
							return errors.New("producer consumer failed to start")
						}
					}
				}
			} else {
				return errors.New("producer failed to start")
			}
		}
	}

	log.Println("Pipeline started")
	return nil
}

// Stop sends the pipeline by sending the done signal
// there's no guarantee on how long it will take to stop
func (pipeline *Pipeline) Stop() {
	log.Printf("Sending stop signal to the pipeline")
	close(pipeline.done)
	log.Printf("Waiting for pipeline to stop...")
	// Give the worker time to stop
	time.Sleep(5 * time.Second)
}

// returns the list of consumers for a given producer identifier
func (pipeline Pipeline) consumers(producerIdentifer string) []string {
	consumers := make([]string, 0)
	for identifer, cfg := range pipeline.stageConfigMap {
		if slices.Contains(cfg.SubcribedTo, producerIdentifer) {
			consumers = append(consumers, identifer)
		}
	}
	return consumers
}

// producerWorker implements the worker goroutine(s) that gets the payload from the
// Producer implementation and puts it in the producer queue. ProducerConsumer(s) or Consumer(s)
// that are subscribed to the producer can read the payload from this queue
type producerWorker struct {
	// send only producer queue
	queue       chan Payload
	BufferLimit int
	WorkerCount int
	Producer    Producer
}

func (pw producerWorker) Start(done <-chan struct{}) (chan Payload, error) {
	pw.queue = make(chan Payload, pw.BufferLimit)

	err := pw.Producer.Start()
	if err != nil {
		return nil, err
	}

	var wg sync.WaitGroup
	wg.Add(pw.WorkerCount)

	// start the worker based on the worker count
	for workerIndex := range pw.WorkerCount {
		log.Printf("Producer worker %d started", workerIndex)

		go func(queue chan Payload) {
			defer wg.Done()

			// producer just keeps producing until the done signal is received
			for {
				select {
				case <-done:
					return
				default:
					payloads, err := pw.Producer.HandleDemand(DEFAULT_DEMAND_COUNT)
					if err != nil {
						log.Printf("Worker %d demand error: %s", workerIndex, err)
						// Consider how to handle errors (retry, break, etc.)
						continue
					}

					for _, payload := range payloads {
						select {
						case pw.queue <- payload:
						case <-done:
							return
						}
					}
				}
			}
		}(pw.queue)
	}

	// Close the queue when all workers are done
	go func() {
		wg.Wait()
		close(pw.queue)
	}()

	return pw.queue, nil
}

type consumerWorker struct {
	Consumer Consumer
}

func (cw consumerWorker) Start(done <-chan struct{}, in chan Payload) (chan Payload, error) {
	return nil, nil
}

type producerConsumerWorker struct {
	producerConsumer ProducerConsumer
}

func (pcw producerConsumerWorker) Start(done <-chan struct{}, in chan Payload) (chan Payload, error) {
	return nil, nil
}
