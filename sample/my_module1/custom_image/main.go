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

	cfp := []config.Point{}

	if cfg := state.FindConfig(module, "api_key"); cfg == nil {
		description := `Hello <a href="https://dash.cloudflare.com/profile/api-tokens">here</a>.`

		cfp = append(cfp, config.Point{
			Identifier:  "api_key",
			Name:        "API Key",
			Description: &description,
			Kind:        config.Secret,
		})
	}

	if cfg := state.FindConfig(module, "email"); cfg == nil {
		cfp = append(cfp, config.Point{
			Identifier: "email",
			Name:       "Email",
			Kind:       config.String,
		})
	}

	return cfp, nil
}

func main() {
	wingman.Start(&MyModule{})
}
