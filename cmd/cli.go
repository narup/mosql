package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/narup/mosql/export"
	cli "github.com/urfave/cli/v2"
)

func main() {
	export.Setup()
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
	switch ctx.Command.FullName() {
	case "init":
		return handleExportInitAction(ctx)
	case "generate-mappings":
		return handleExportGenerateMappings(ctx)
	default:
		return errors.New("invalid command")
	}
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

func handleExportInitAction(ctx *cli.Context) error {
	namespace := ctx.String("namespace")

	fmt.Printf("Initalizing export for namespace '%s'. Provide a few more details:\n", namespace)

	details := export.InitData{}
	for {
		details = getExportDetails(details)
		// Check if user confirmed to save
		if strings.ToUpper(details.Save) == "Y" {
			fmt.Println("Saving the export details...")
			break // exit the loop if user confirmed to save
		} else {
			fmt.Println("\n\nYou can change the export details again. Press 'return' to keep the same value. To quit press ctrl+c")
		}
	}

	exportID, err := export.InitializeExport(context.Background(), namespace, details)
	if err != nil {
		return fmt.Errorf("failed to initialize export, error %s", err)
	}
	nextPrompt := `Now you can either generate a default schema mapping or run export with default mapping with following commands
    1) $ mosql export generate_mapping --namespacce <namespace_value> --dir-path <dir_path_value>
    2) $ mosql export start --namespace <namespace_value> --type <type_value>`
	fmt.Printf("\n✅ Export created with namespace `%s`. Export ID `%d`\n\n %s\n", namespace, exportID, nextPrompt)

	return nil
}

func handleExportGenerateMappings(ctx *cli.Context) error {
	namespace := ctx.String("namespace")
	filePath := ctx.String("dir-path")

	_, err := os.Stat(filePath)
	if os.IsNotExist(err) {
		err = os.MkdirAll(filePath, 0755)
		if err != nil {
			return err
		}
	}

	return export.GenerateSchemaMapping(context.Background(), namespace, filePath)
}

func getExportDetails(currentValues export.InitData) export.InitData {
	details := export.InitData{
		SourceDatabaseName:                  promptInput(currentValues.SourceDatabaseName, getPromptText("> Source database name", currentValues.SourceDatabaseName), true),
		SourceDatabaseConnectionString:      promptInput(currentValues.SourceDatabaseConnectionString, getPromptText("> Source database connection string", currentValues.SourceDatabaseConnectionString), true),
		DestinationDatabaseName:             promptInput(currentValues.DestinationDatabaseName, getPromptText("> Destination database name", currentValues.DestinationDatabaseName), true),
		DestinationDatabaseConnectionString: promptInput(currentValues.DestinationDatabaseConnectionString, getPromptText("> Destination database connection string", currentValues.DestinationDatabaseConnectionString), true),
		DestinationDatabaseType:             promptInput(currentValues.DestinationDatabaseType, getPromptText("> Destination database type (default is postgres)", currentValues.DestinationDatabaseType), false),
		CollectionsToExclude:                promptInput(currentValues.CollectionsToExclude, getPromptText("> Collections to exclude (comma separated)", currentValues.CollectionsToExclude), false),
		CollectionsToInclude:                promptInput(currentValues.CollectionsToInclude, getPromptText("> Collections to include (comma separated, no value means include all collections)", currentValues.CollectionsToInclude), false),
		UserName:                            promptInput(currentValues.UserName, getPromptText("> User name (optional)", currentValues.UserName), false),
		Email:                               promptInput(currentValues.Email, getPromptText("> Email (optional)", currentValues.Email), false),
		Save:                                promptInput("", getPromptText("> Save (Y/N - Press Y to save and N to change the export details)", ""), true),
	}

	return details
}

func promptInput(currentValue, prompt string, required bool) string {
	reader := bufio.NewReader(os.Stdin)
	for {
		fmt.Print(prompt)
		input, _ := reader.ReadString('\n')
		input = strings.TrimSpace(input)
		if input == "" && currentValue != "" {
			// use the current value if input is empty
			input = currentValue
		}
		if input == "" && required {
			fmt.Println("Required input. Please provide a value.")
		} else {
			return input
		}
	}
}

func getPromptText(defaultPrompt, currentValue string) string {
	if strings.TrimSpace(currentValue) == "" {
		return fmt.Sprintf("%s: ", defaultPrompt)
	} else {
		return fmt.Sprintf("%s (current value `%s`): ", defaultPrompt, currentValue)
	}
}
