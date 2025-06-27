package main

import (
	"context"

	"github.com/BSFishy/mora-manager/config"
	"github.com/BSFishy/mora-manager/wingman"
)

type MyModule struct{}

func (m *MyModule) GetConfigPoints(ctx context.Context) ([]config.Point, error) {
	state := wingman.GetState(ctx)
	module := wingman.ModuleName(ctx)

	if cfg := state.FindConfig(module, "test"); cfg != nil {
		return []config.Point{}, nil
	}

	return []config.Point{
		{
			Identifier: "test",
			Name:       "Testing",
			Kind:       config.Secret,
		},
	}, nil
}

func main() {
	wingman.Start(&MyModule{})
}
