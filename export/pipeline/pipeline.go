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
}

type ProducerConsumer interface {
	Stage
	HandleDemand() DataEvent
	Consume(dataEvent DataEvent)
}

type Consumer interface {
	Stage
	Consume()
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
	}
	return nil
}
