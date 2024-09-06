package main

import (
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
		exportGenerateMappingsCommand(),
		exportLoadMappingsCommand(),
		exportListCommand(),
		exportShowCommand(),
		exportDeleteCommand(),
		exportStartCommand(),
	}
}

func exportInitCommand() *cli.Command {
	return &cli.Command{
		Name:         "init",
		Usage:        "Initialize new export",
		Flags:        []cli.Flag{namespaceFlag()},
		Action:       handleExportActions,
		OnUsageError: onExportCommandUsageErrors,
	}
}

func exportGenerateMappingsCommand() *cli.Command {
	return &cli.Command{
		Name:         "generate-mappings",
		Usage:        "Generate default mappings for the export with given namespace. Default mappings converts Mongo collections and its keys to SQL tables and columns with default type conversions",
		Flags:        []cli.Flag{namespaceFlag(), pathFlag()},
		Action:       handleExportActions,
		OnUsageError: onExportCommandUsageErrors,
	}
}

func exportLoadMappingsCommand() *cli.Command {
	return &cli.Command{
		Name:         "load-mappings",
		Usage:        "Load mappings for the export with given namespace from the directory path. This is used to load customized mappings that are generated or handwriten mappings",
		Flags:        []cli.Flag{namespaceFlag(), pathFlag()},
		Action:       handleExportActions,
		OnUsageError: onExportCommandUsageErrors,
	}
}

func exportListCommand() *cli.Command {
	return &cli.Command{
		Name:         "list",
		Usage:        "List all the saved exports",
		Action:       handleExportActions,
		OnUsageError: onExportCommandUsageErrors,
	}
}

func exportShowCommand() *cli.Command {
	return &cli.Command{
		Name:         "show",
		Usage:        "Show the details of the saved export for a given namespace",
		Flags:        []cli.Flag{namespaceFlag()},
		Action:       handleExportActions,
		OnUsageError: onExportCommandUsageErrors,
	}
}

func exportDeleteCommand() *cli.Command {
	return &cli.Command{
		Name:         "delete",
		Usage:        "Delete the export for a given namespace",
		Flags:        []cli.Flag{namespaceFlag()},
		Action:       handleExportActions,
		OnUsageError: onExportCommandUsageErrors,
	}
}

func exportStartCommand() *cli.Command {
	return &cli.Command{
		Name:         "start",
		Usage:        "Start the export based on the type value of 'full' or 'change-stream'",
		Flags:        []cli.Flag{namespaceFlag(), typeFlag()},
		Action:       handleExportActions,
		OnUsageError: onExportCommandUsageErrors,
	}
}

func handleExportActions(ctx *cli.Context) error {
	command := ctx.Command.FullName()
	if ctx.NumFlags() == 0 || ctx.String("namespace") == "" {
		return fmt.Errorf("invalid command, run 'mosql export %s help' for usage", command)
	}
	namespace := ctx.String("namespace")
	fmt.Printf("Initalizing namespace: %s\n", namespace)

	return nil
}

func onExportCommandUsageErrors(ctx *cli.Context, err error, _ bool) error {
	command := ctx.Command.FullName()
	return fmt.Errorf("eror: %s, run 'mosql export %s help' for usage", err, command)
}

func typeFlag() cli.Flag {
	return flag("type", "t", "Expor type 'full' or 'change-stream'")
}

func pathFlag() cli.Flag {
	return flag("dir-path", "dp", "Dir path of all the mapping files")
}

func namespaceFlag() cli.Flag {
	return flag("namespace", "ns", "Namespace value of the export")
}

func flag(name, alias, usage string) cli.Flag {
	return &cli.StringFlag{
		Name:    name,
		Aliases: []string{alias},
		Usage:   usage,
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
