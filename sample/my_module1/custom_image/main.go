package main

import (
	"context"
	"fmt"

	"github.com/BSFishy/mora-manager/state"
	"github.com/BSFishy/mora-manager/wingman"
)

type MyModule struct{}

func (m *MyModule) GetConfigPoints(ctx context.Context, state state.State) ([]wingman.ConfigPoint, error) {
	module := wingman.ModuleName(ctx)
	if cfg := state.FindConfig(module, "test"); cfg != nil {
		return []wingman.ConfigPoint{}, nil
	}

	return []wingman.ConfigPoint{
		{
			Identifier: "test",
			Name:       "Testing",
		},
	}, nil
}

func main() {
	fmt.Printf("hello world!\n")

	wingman.Start(&MyModule{})
}
