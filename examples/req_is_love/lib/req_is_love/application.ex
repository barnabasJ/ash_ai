defmodule ReqIsLove.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ReqIsLoveWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:req_is_love, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ReqIsLove.PubSub},
      # Start a worker by calling: ReqIsLove.Worker.start_link(arg)
      # {ReqIsLove.Worker, arg},
      # Start to serve requests, typically the last entry
      ReqIsLoveWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ReqIsLove.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ReqIsLoveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
