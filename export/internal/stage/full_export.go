package stage

import (
	"github.com/narup/mosql/export/internal/core"
	"github.com/narup/mosql/export/pipeline"
)

// FullExportProducer producer stage for Mongo to postgres full data epxort
// This implements pipeline.Stage and pipeline.Producer interface
type FullExportProducer struct {
	Export core.Export
}

func (fep *FullExportProducer) Identifier() string {
	return "full_export_producer"
}

func (fep *FullExportProducer) Init() error {
	return nil
}

func (fep *FullExportProducer) Produce() ([]pipeline.Payload, error) {
	payload := make([]pipeline.Payload, 0)
	return payload, nil
}

// FullExportProducerConsumer is the middle stage ProducerConsumer
// this stage actually reads the collection name from the producer and
// loads the data from the MongoDB and sends it to the SQL consumer to
// convert to SQL messages
type FullExportProducerConsumer struct {
	Export core.Export
}

func (fepc *FullExportProducerConsumer) Identifier() string {
	return "full_export_producer_consumer"
}

func (fepc *FullExportProducerConsumer) Init() error {
	// initialization - connection to MongoDB etc
	return nil
}

func (fepc *FullExportProducerConsumer) Process(payload []pipeline.Payload) ([]pipeline.Payload, error) {
	return nil, nil
}

type FullExportConsumer struct {
	Export        core.Export
	subscriptions []string
}

func (fec *FullExportConsumer) Identifier() string {
	return "full_export_consumer"
}

func (fec *FullExportConsumer) Init() error {
	// initialization - connection to MongoDB etc
	return nil
}

func (fec *FullExportConsumer) Consume(payload []pipeline.Payload) error {
	return nil
}

func CreateFullExportPipeline(export core.Export) (*pipeline.Pipeline, error) {
	fullExportPipeline := new(pipeline.Pipeline)
	fullExportPipeline.Name = export.Namespace

	fep := new(FullExportProducer)
	fep.Export = export

	fepc := new(FullExportProducerConsumer)
	fepc.Export = export

	fec := new(FullExportConsumer)
	fec.Export = export

	fullExportPipeline.AddStage(fep, pipeline.StageConfig{
		Type:       pipeline.StageTypeProducer,
		Identifier: "producer_stage_1_segment_collections",
	})
	fullExportPipeline.AddStage(fepc, pipeline.StageConfig{
		Type:        pipeline.StageTypeProducerConsumer,
		Identifier:  "producer_consumer_stage_2_read_collection",
		SubcribedTo: []string{"FullExportProducer"},
	})
	fullExportPipeline.AddStage(fec, pipeline.StageConfig{
		Type:        pipeline.StageTypeConsumer,
		Identifier:  "consumer_stage_3_insert_sql",
		SubcribedTo: []string{"FullExportProducerConsumer"},
	})

	return fullExportPipeline, nil
}
