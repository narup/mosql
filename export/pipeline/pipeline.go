package pipeline

import "errors"

type DataEvent interface {
	GetData() interface{}
}

type Stage interface {
	Init()
	Start()
	Type() string
}

type Producer interface {
	Stage
	HandleDemand() DataEvent
	Subscribe()
}

type Consumer interface {
	Stage
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
	producers         []*Producer
	producerConsumers []*ProducerConsumer
	consumers         []*Consumer
}

func (p *Pipeline) AddStage(s Stage) error {
	switch s.Type() {
	case "producer":
		if p.producers == nil {
			p.producers = make([]*Producer, 0)
		}
		producer, ok := s.(Producer)
		if ok {
			p.producers = append(p.producers, &producer)
		} else {
			return errors.New("invalid producer type")
		}
	case "ProducerConsumer":
		if p.producerConsumers == nil {
			p.producerConsumers = make([]*ProducerConsumer, 0)
		}
		pc, ok := s.(ProducerConsumer)
		if ok {
			p.producerConsumers = append(p.producerConsumers, &pc)
		} else {
			return errors.New("invalid producer consumer")
		}
	}
	return nil
}
