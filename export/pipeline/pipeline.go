// pipeline is a minimal data pipeline framework that can be used to build
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

var (
	DEFAULT_DEMAND_COUNT = 100
	DEFAULT_BUFFER_COUNT = 100
)

// Message represents the message passed between
// data pipleline stages. ID is assigned by the pipeline
// manager. ID is used for acknowledgment as well
type Message struct {
	ID       string
	Payloads []Payload
	Ack      chan string // Channel for acknowledgments
}

// Payload marker interface to represent the data
// between stages wrapped inside Message
type Payload interface{}

type Stage interface {
	Identifier() string
	Init() error
}

// StageType defines the different stage type supported in the pipleline
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
	WorkerCount int
	BufferLimit int
	SubcribedTo []string // only applicable for stage type "Consumer"
}

// Producer is responsible for producing data
type Producer interface {
	Stage
	Produce(demandCount int) ([]Payload, error)
}

type Consumer interface {
	Stage
	Consume(payload []Payload) error
}

type ProducerConsumer interface {
	Stage
	Process(payload []Payload) ([]Payload, error)
}

// Pipeline implements end-to-end data pipeline backed by
// workers and go bufffered channels for queues - input, output, demand and done queues
// all are based on the go buffer channel. Each stages can be run in parallel by using the
// WorkerCount > 1. But, it's user responsibility to make sure design the data pipeline in
// a way it can be parallelized.
type Pipeline struct {
	done           chan struct{} // done channel to stop the pipeline
	demand         chan int      // demand channel to demand data from the stages
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
		if cfg.BufferLimit == 0 {
			cfg.BufferLimit = DEFAULT_BUFFER_COUNT
		}
		if cfg.WorkerCount == 0 {
			// by default only use 1 worker, no parallel processing
			cfg.WorkerCount = 1
		}
		p.stageConfigMap[cfg.Identifier] = cfg
	}

	return nil
}

// Start starts the data pipeline based on all the added
// stages of different types
func (pipeline *Pipeline) Start() error {
	log.Println("Pipeline: starting...")

	// channel to cancel the pipeline data flow
	pipeline.done = make(chan struct{})
	defer close(pipeline.done)

	// channel to track demand to manage back pressure
	pipeline.demand = make(chan int, 1)
	defer close(pipeline.demand)

	for identifier, stage := range pipeline.stageMap {
		cfg := pipeline.stageConfigMap[identifier]
		if cfg.Type == StageTypeProducer {
			p, ok := stage.(Producer)
			if ok {
				log.Printf("Pipeline: starting producer(%s) worker with worker count %d and buffer limit %d\n", p.Identifier(), cfg.WorkerCount, cfg.BufferLimit)
				// start a worker to support Producer operations
				pw := producerWorker{
					Producer:    p,
					BufferLimit: cfg.BufferLimit,
					WorkerCount: cfg.WorkerCount,
				}
				producerQueue := pw.Start(pipeline.demand, pipeline.done)

				log.Printf("Pipeline: start consumers or producer consumers subscribed to producer (%s)\n", p.Identifier())

				// find consumers for a producer above
				err := pipeline.startConsumers(producerQueue, identifier)
				if err != nil {
					return err
				}
			} else {
				log.Printf("Pipeline: producer start failed. Stage not recognized as a producer")
				return errors.New("producer failed to start")
			}
		}
	}

	log.Println("Pipeline: started and running")
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

func (pipeline Pipeline) startConsumers(producerQueue chan Message, producerIdentifier string) error {
	for _, consumerIdentifier := range pipeline.consumers(producerIdentifier) {
		stage := pipeline.stageMap[consumerIdentifier]
		cfg := pipeline.stageConfigMap[consumerIdentifier]

		if cfg.Type == StageTypeProducerConsumer {
			pc, ok := stage.(ProducerConsumer)
			if ok {
				pcw := producerConsumerWorker{
					producerConsumer: pc,
					WorkerCount:      cfg.WorkerCount,
					BufferLimit:      cfg.BufferLimit,
				}
				pcQueue := pcw.Start(producerQueue, pipeline.demand, pipeline.done)
				// producer consumer may have other consumbers
				pipeline.startConsumers(pcQueue, cfg.Identifier)
			} else {
				return errors.New("producer consumer failed to start")
			}
		}

		if cfg.Type == StageTypeConsumer {
			c, ok := stage.(Consumer)
			if ok {
				cw := consumerWorker{
					Consumer:    c,
					WorkerCount: cfg.WorkerCount,
				}
				cw.Start(producerQueue, pipeline.demand, pipeline.done)
			} else {
				return errors.New("consumer failed to start")
			}
		}
	}

	return nil
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
	BufferLimit int
	WorkerCount int
	Producer    Producer
}

// Start starts the producer worker
func (pw producerWorker) Start(demand <-chan int, done <-chan struct{}) chan Message {
	outQueue := make(chan Message, pw.BufferLimit)

	var wg sync.WaitGroup
	wg.Add(pw.WorkerCount)

	// start the worker based on the worker count
	for workerIndex := range pw.WorkerCount {
		log.Printf("ProduceR: worker %d started", workerIndex)

		// start parallel workers based on the worker count
		go func(outQueue chan<- Message, demandQueue <-chan int, doneQueue <-chan struct{}) {
			defer wg.Done()

			// producer just keeps producing until the done signal is received
			// demand count is received via demand queue
			for demandCount := range demandQueue {
				select {
				case <-doneQueue:
					log.Println("Producer: done singal received. Exiting producer")
					// TODO: check if we need to do callback to the producer implementation
					return
				default:
					log.Printf("Producer: received demand for %d\n", demandCount)
					payloads, err := pw.Producer.Produce(demandCount)
					if err != nil {
						log.Printf("Producer: worker %d, handle demand error: %s\n", workerIndex, err)
						// Consider how to handle errors (retry, break, etc.)
						continue
					}

					log.Printf("Producer: %d payloads from the producer implementation\n", len(payloads))

					// construct message to send with a payload from the Producer implementation
					msg := Message{
						ID:       fmt.Sprintf("%d", time.Now().UnixMicro()),
						Payloads: payloads,
						Ack:      make(chan string, 1),
					}
					// send the message to out queue
					outQueue <- msg

					log.Println("Producer: message sent to producer queue. Wait for acknowledgment and timeout")

					select {
					case <-doneQueue:
						log.Println("Producer: done singal received. Exiting producer")
						return
					case ackID := <-msg.Ack: // Wait for acknowledgment
						fmt.Printf("Producer: message %s acknowledged\n", ackID)
						// TODO: can call acknowledgment callback to the producer or pipeline
					case <-time.After(10 * time.Second):
						// TODO: can call timeout callback to the producer or pipeline
						fmt.Printf("Producer: message %s timed out\n", msg.ID)
					}
				}
			}
		}(outQueue, demand, done)
	}

	// Close the queue when all workers are done
	go func() {
		wg.Wait()
		log.Println("Producer: close producer queue")
		close(outQueue)
	}()

	return outQueue
}

type producerConsumerWorker struct {
	producerConsumer ProducerConsumer
	WorkerCount      int
	BufferLimit      int
}

func (pcw producerConsumerWorker) Start(producer chan Message, demand chan int, done <-chan struct{}) chan Message {
	// output queue where producer consumer sends the processed message to the next stage
	outQueue := make(chan Message, pcw.BufferLimit)

	for workerIndex := range pcw.WorkerCount {
		log.Printf("ProducerConsumer: worker %d started", workerIndex)

		go func(inQueue <-chan Message, demandQueue <-chan int, doneQueue <-chan struct{}) {
			for {
				select {
				case <-doneQueue:
					log.Println("ProducerConsumer: done singal received. Exiting producer consumer")
					return
				default:
					for inMsg := range inQueue {
						processedPayloads, err := pcw.producerConsumer.Process(inMsg.Payloads)
						if err != nil {
							log.Printf("ProducerConsumer: data procesisng error: %s", err)
							// TODO: handle error
						}
						processedMsg := Message{
							ID:       inMsg.ID,
							Payloads: processedPayloads,
							Ack:      inMsg.Ack,
						}

						// Forward the message
						select {
						case <-doneQueue:
							log.Println("ProducerConsumer: done singal received. Exiting producer consumer")
						case <-demandQueue:
							log.Println("ProducerConsumer: demand received. Send data")
							outQueue <- processedMsg
						case <-time.After(10 * time.Second):
							// If no demand, skip this message
							fmt.Printf("ProducerConsumer: message %s timed out\n", inMsg.ID)
							inMsg.Ack <- inMsg.ID
						}
					}
				}
			}
		}(producer, demand, done)
	}

	return outQueue
}

type consumerWorker struct {
	WorkerCount int
	Consumer    Consumer
}

func (cw consumerWorker) Start(producer chan Message, demand chan int, done <-chan struct{}) {
	for workerIndex := range cw.WorkerCount {
		log.Printf("Consumer: worker %d started\n", workerIndex)

		go func(inQueue <-chan Message, demandQueue chan int, doneQueue <-chan struct{}) {
			// listen in loop until done signal is received
			for {
				select {
				case <-doneQueue:
					log.Println("Consumer: done singal received. Exiting producer consumer")
					return

				default:
					for msg := range inQueue {
						// Process the message
						err := cw.Consumer.Consume(msg.Payloads)
						if err != nil {
							log.Printf("Consumer: consumer data error: %s\n", err)
						}

						log.Printf("Consumer: consumed data- %v\n", msg)
						log.Printf("Consumer: send the message acknowledgment for message ID %s and also demand more data\n", msg.ID)
						msg.Ack <- msg.ID
						demandQueue <- DEFAULT_DEMAND_COUNT // TODO: use demand algorithm
					}
				}
			}
		}(producer, demand, done)
	}
}
