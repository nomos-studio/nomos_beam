defmodule NomosBeam.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NomosBeamWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:nomos_beam, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NomosBeam.PubSub},
      NomosBeam.KeyboardServer,
      NomosBeam.TxlogBuffer,
      NomosBeam.NousPort,
      NomosBeam.AionSupervisor,
      NomosBeam.ScSynth,
      NomosBeam.DisplayClock,
      # Phase 3: NomosBeam.CtrlTreeProxy — ctrl-tree IPC bridge
      # Phase 4: NomosBeam.MountTable    — mDNS + Khepri peer discovery
      # Phase 5: NomosBeam.BeatSupervisor, NomosBeam.ConductorArc
      NomosBeamWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: NomosBeam.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NomosBeamWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
