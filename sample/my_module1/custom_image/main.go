package main

import (
	"context"

	"github.com/BSFishy/mora-manager/expr"
	"github.com/BSFishy/mora-manager/point"
	"github.com/BSFishy/mora-manager/value"
	"github.com/BSFishy/mora-manager/wingman"
)

type MyModule struct{}

func (m *MyModule) GetConfigPoints(ctx context.Context, deps wingman.WingmanContext) ([]point.Point, error) {
	state := deps.GetState()
	module := deps.GetModuleName()

	cfp := []point.Point{}

	if cfg := state.FindConfig(module, "api_key"); cfg == nil {
		description := `Hello <a href="https://dash.cloudflare.com/profile/api-tokens">here</a>.`

		cfp = append(cfp, point.Point{
			Identifier:  "api_key",
			Name:        "API Key",
			Description: &description,
			Kind:        point.Secret,
		})
	}

	if cfg := state.FindConfig(module, "email"); cfg == nil {
		cfp = append(cfp, point.Point{
			Identifier: "email",
			Name:       "Email",
			Kind:       point.String,
		})
	}

	return cfp, nil
}

func (m *MyModule) GetFunctions(ctx context.Context, deps wingman.WingmanContext) (map[string]expr.ExpressionFunction, error) {
	return map[string]expr.ExpressionFunction{
		"cloudflared_token": {
			MinArgs: 0,
			MaxArgs: 0,
			Evaluate: func(ctx context.Context, deps expr.EvaluationContext, args expr.Args) (value.Value, []point.Point, error) {
				return value.NewString("hello world!"), nil, nil
			},
		},
	}, nil
}

func main() {
	wingman.Start(&MyModule{})
}
