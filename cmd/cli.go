package main

import (
	"errors"
	"fmt"
	"log"
	"os"

	cli "github.com/urfave/cli/v2"
)

func main() {
	app := &cli.App{
		Name: "mosql",
		Commands: []*cli.Command{
			{
				Name:        "export",
				Usage:       "handle export related operations",
				Subcommands: exportCommands(),
			},
			{
				Name:    "admin",
				Aliases: []string{"a"},
				Usage:   "start admin console",
				Action: func(cCtx *cli.Context) error {
					fmt.Println("Admin console not ready yet")
					return nil
				},
			},
		},
	}

	if err := app.Run(os.Args); err != nil {
		log.Fatal(err)
	}
}

func exportCommands() []*cli.Command {
	return []*cli.Command{
		exportInitCommand(),
	}
}

func exportInitCommand() *cli.Command {
	return &cli.Command{
		Name:  "init",
		Usage: "Initialize new export",
		Flags: []cli.Flag{namespaceFlag()},
		Action: func(ctx *cli.Context) error {
			if ctx.NumFlags() == 0 || ctx.String("namespace") == "" {
				return errors.New("invalid command, run 'mosql export init help' for usage")
			}
			namespace := ctx.String("namespace")
			fmt.Printf("Initalizing namespace: %s\n", namespace)

			return nil
		},
		OnUsageError: func(ctx *cli.Context, err error, isSubcommand bool) error {
			return errors.New("invalid command. run 'mosql export init help' for usage")
		},
	}
}

func exportGenerateMappingsCommand() *cli.Command {
	return &cli.Command{
		Name:  "generate-mappings",
		Usage: "Generate default mappings for the export with given namespace. Default mappings converts Mongo collections and its keys to SQL tables and columns with default type conversions",
		Flags: []cli.Flag{namespaceFlag()},
		Action: func(ctx *cli.Context) error {
			if ctx.NumFlags() == 0 || ctx.String("namespace") == "" {
				return errors.New("invalid command, run 'mosql export generate-mappings help' for usage")
			}
			namespace := ctx.String("namespace")
			fmt.Printf("Initalizing namespace: %s\n", namespace)

			return nil
		},
		OnUsageError: func(ctx *cli.Context, err error, isSubcommand bool) error {
			return errors.New("invalid command. run 'mosql export generate-mappings help' for usage")
		},
	}
}

func namespaceFlag() cli.Flag {
	return &cli.StringFlag{
		Name:    "namespace",
		Aliases: []string{"ns"},
		Usage:   "Initalize export with unique namespace value",
	}
}

func initializeExportAction(ctx *cli.Context, namespace string) {
	for {
		var input string
		fmt.Print("Enter something: ")
		fmt.Scanln(&input)
		fmt.Println("You entered:", input)
	}
}
