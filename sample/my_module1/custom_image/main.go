package main

import (
	"context"
	"fmt"

	"github.com/cloudflare/cloudflare-go/v4"
	"github.com/cloudflare/cloudflare-go/v4/option"
	"github.com/cloudflare/cloudflare-go/v4/zero_trust"

	"github.com/BSFishy/mora-manager/expr"
	"github.com/BSFishy/mora-manager/kube"
	"github.com/BSFishy/mora-manager/point"
	"github.com/BSFishy/mora-manager/state"
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

// TODO: make these configurable
const (
	accountId  = "0fb96e014f4d50adf73b571840427dc3"
	tunnelName = "test tunnel"
)

func (m *MyModule) GetFunctions() map[string]expr.ExpressionFunction {
	return map[string]expr.ExpressionFunction{
		"cloudflared_token": {
			MinArgs: 0,
			MaxArgs: 0,
			Evaluate: func(ctx context.Context, deps expr.EvaluationContext, args expr.Args) (value.Value, []point.Point, error) {
				st := deps.GetState()
				module := deps.GetModuleName()

				if cfg := st.FindConfig(module, "cloudflared_token"); cfg != nil {
					return value.NewSecret(string(cfg.Value)), nil, nil
				}

				apiKeyConfig := st.FindConfig(module, "api_key")
				emailConfig := st.FindConfig(module, "email")

				if apiKeyConfig == nil || emailConfig == nil {
					return nil, nil, fmt.Errorf("invalid state")
				}

				apiKey := string(apiKeyConfig.Value)
				email := string(emailConfig.Value)

				apiKeySecret, err := kube.GetSecret(ctx, deps, apiKey)
				if err != nil {
					return nil, nil, fmt.Errorf("getting api key secret: %w", err)
				}

				client := cloudflare.NewClient(option.WithAPIKey(string(apiKeySecret)), option.WithAPIEmail(email))
				tunnels, err := client.ZeroTrust.Tunnels.Cloudflared.List(ctx, zero_trust.TunnelCloudflaredListParams{
					AccountID: cloudflare.F(accountId),
				})
				if err != nil {
					return nil, nil, fmt.Errorf("listing tunnels: %w", err)
				}

				var tunnelId string
				for _, tunnel := range tunnels.Result {
					if tunnel.Name == tunnelName {
						tunnelId = tunnel.ID
						break
					}
				}

				if tunnelId == "" {
					tunnel, err := client.ZeroTrust.Tunnels.Cloudflared.New(ctx, zero_trust.TunnelCloudflaredNewParams{
						AccountID: cloudflare.F(accountId),
						Name:      cloudflare.F(tunnelName),
					})
					if err != nil {
						return nil, nil, fmt.Errorf("creating tunnel: %w", err)
					}

					tunnelId = tunnel.ID
				}

				token, err := client.ZeroTrust.Tunnels.Cloudflared.Token.Get(ctx, tunnelId, zero_trust.TunnelCloudflaredTokenGetParams{
					AccountID: cloudflare.F(accountId),
				})
				if err != nil {
					return nil, nil, fmt.Errorf("getting token: %w", err)
				}

				secret := kube.NewSecret(deps, "cloudflared_token", []byte(*token))
				if err := kube.Deploy(ctx, deps, secret); err != nil {
					return nil, nil, fmt.Errorf("deploying token secret: %w", err)
				}

				st.Configs = append(st.Configs, state.StateConfig{
					ModuleName: module,
					Name:       "cloudflared_token",
					Kind:       point.Secret,
					Value:      []byte(secret.Name()),
				})

				return value.NewSecret(secret.Name()), nil, nil
			},
		},
	}
}

func main() {
	wingman.Start(&MyModule{})
}
