package pipeline

import (
	"errors"
	"log"
)

type Payload interface {
	Body() interface{}
}

type Stage interface {
	Init()
	Start() error
	Type() string
}

type Producer interface {
	Stage
	HandleDemand() ([]Payload, error)
}

type Consumer interface {
	Stage
	Subcribe(prodcuer Producer)
	HandleData()
}

type ProducerConsumer interface {
	Stage
	Producer
	Consumer
}

// Pipeline defines end-to-end export Pipeline
type Pipeline struct {
	Name              string
	producers         []Producer
	producerConsumers []ProducerConsumer
	consumers         []Consumer
}

type producerWorker struct {
	// send only queue
	queue       chan<- Payload
	BufferLimit int
	WorkerCount int
	Producer    Producer
}

func (pw producerWorker) Start(done <-chan struct{}) (chan<- Payload, error) {
	pw.queue = make(chan Payload, pw.BufferLimit)

	err := pw.Producer.Start()
	if err != nil {
		return nil, err
	}

	for workerIndex := range pw.WorkerCount {
		// start the worker!
		log.Printf("Producer worker %d started", workerIndex)
		go func(queue chan<- Payload) {
			// TODO: check if this is okay to close in loop
			defer close(pw.queue)
			payloads, err := pw.Producer.HandleDemand()
			if err != nil {
				log.Printf("demand error %s", err)
				// TODO: Handle this better
			}

			for _, payload := range payloads {
				select {
				case queue <- payload:
				case <-done:
					return
				}
			}
		}(pw.queue)
	}

	return pw.queue, nil
}

type consumerWorker struct {
	consumer *Consumer
}

type producerConsumerWorker struct {
	producerConsumer *ProducerConsumer
}

func (p *Pipeline) AddStage(s Stage) error {
	switch s.Type() {
	case "producer":
		if p.producers == nil {
			p.producers = make([]Producer, 0)
		}
		producer, ok := s.(Producer)
		if ok {
			p.producers = append(p.producers, producer)
		} else {
			return errors.New("invalid producer type")
		}
	case "ProducerConsumer":
		if p.producerConsumers == nil {
			p.producerConsumers = make([]ProducerConsumer, 0)
		}
		pc, ok := s.(ProducerConsumer)
		if ok {
			p.producerConsumers = append(p.producerConsumers, pc)
		} else {
			return errors.New("invalid producer consumer")
		}
	case "Consumer":
		if p.consumers == nil {
			p.consumers = make([]Consumer, 0)
		}
		c, ok := s.(Consumer)
		if ok {
			p.consumers = append(p.consumers, c)
		} else {
			return errors.New("invalid consumer")
		}
	}

	return nil
}

func (pipeline *Pipeline) Start() error {
	done := make(chan struct{})
	defer close(done)

	for _, p := range pipeline.producers {
		pw := producerWorker{
			Producer:    p,
			BufferLimit: 5,
			WorkerCount: 3,
		}

		_, err := pw.Start(done)
		if err != nil {
			return err
		}
	}
	for _, pc := range pipeline.producerConsumers {
		err := pc.Start()
		if err != nil {
			return err
		}
	}
	for _, c := range pipeline.consumers {
		err := c.Start()
		if err != nil {
			return err
		}
	}
	return nil
}
