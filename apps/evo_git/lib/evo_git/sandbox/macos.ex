defmodule EvoGit.Sandbox.MacOS do
  @moduledoc """
  macOS sandbox backend using `sandbox-exec`.

  Filesystem policy: WRITES are deny-by-default with an explicit allow list
  (the repo worktree (cwd + `.git`), tmp paths, genesis config/data dirs,
  and build caches); READS are allow-by-default at the ROOT —
  `(allow file-read* (subpath "/"))` makes the whole filesystem readable so
  agents can use user-installed tools anywhere (Homebrew `/opt/homebrew`,
  Intel `/usr/local`, `/Applications`, custom `/opt` installs, nix,
  asdf/mise). Protection for credential stores comes from a deny-read list
  (SBPL deny rules take precedence over allow rules): home-based sensitive
  dirs (`~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.config/sops`,
  `~/.git-credentials`, `~/.netrc`, `~/.password-store`,
  `~/Library/Keychains`, `~/.npmrc`, `~/.pypirc`, `~/.docker`, `~/.gem`)
  plus system-level sensitive locations (`/etc/ssh`, `/var/root`,
  `/etc/master.passwd`, `/var/db/dslocal`, `/var/db/Keychains` — both
  `/etc`↔`/private/etc` and `/var`↔`/private/var` spellings). This is a
  deliberate trade-off: sandboxed agents can read any user-readable file,
  mitigated by the deny list — the pre-hardening read model, restored by
  user decision because enumerating every legitimate tool path is
  unmaintainable. The host `$TMPDIR` stays readable so temp files written
  before sandbox invocation (e.g. skill scripts) remain usable. Writes are
  restricted to the worktree, tmp paths, genesis dirs, and
  package-manager/toolchain cache dirs, with deny-write rules for sensitive
  dirs as defense in depth.

  Also enforces a process-count limit (`(limit number N)`, see
  `@max_processes`) and keeps network default-allowed (agents run
  `git fetch/push`, `mix deps.get`, `curl`, and web tools). If the host's
  `sandbox-exec` rejects the `(limit ...)` syntax, profile selection probes
  a harmless command with and without
  the limit and caches the supported profile. User commands execute once.
  """

  @behaviour EvoGit.Sandbox.Behaviour

  require Logger

  alias EvoGit.{Nix, Platform, Sandbox.Helpers}

  # Maximum number of concurrently live processes/threads the sandboxed
  # process may spawn, enforced via SBPL `(limit number N)`. Tunable —
  # chosen to fit `mix test`-style parallel workloads (worker processes,
  # compiler ports) while still capping a runaway agent's fork bombs.
  @max_processes 200

  # Foreground and background execution share the result of a harmless
  # native profile probe. true means the process-count rule is unsupported.
  @process_limit_rejected_key {EvoGit.Sandbox.MacOS, :process_limit_rejected}

  # Built-in writable cache dirs (home-relative) for package managers and
  # toolchains (`mix deps.get`, `npm install`, `cargo build`). This is the
  # DEFAULT list emitted as `(allow file-write* (subpath "<home>/<dir>"))`
  # (rule group 12) when the user has NOT set `[sandbox] write_paths`. When
  # set, the user's list REPLACES this one wholesale (even an empty list) —
  # see `Helpers.resolve_write_paths/3`.
  @default_cache_dirs [
    ".cache",
    ".local/share",
    ".local/state",
    ".cargo",
    ".rustup",
    ".mix",
    ".hex",
    ".npm",
    ".yarn",
    ".bun",
    ".m2",
    ".gradle",
    "go"
  ]

  @doc "Returns true when sandbox mode allows sandbox-exec on macOS."
  @spec enabled?() :: boolean()
  def enabled? do
    case EvoGit.Config.resolve([:sandbox, :mode]) do
      :enabled -> true
      :disabled -> false
      :auto -> Platform.sandbox_exec_available?()
    end
  end

  @doc "No initialization needed for sandbox-exec."
  @spec ensure_initialized() :: :ok
  def ensure_initialized, do: :ok

  @doc "Runs command via sandbox-exec with a generated SBPL profile."
  @spec run(String.t(), String.t(), [String.t()], String.t() | nil) ::
          {String.t(), non_neg_integer()}
  def run(cwd, executable, args \\ [], repo_root \\ nil) when is_list(args) do
    if enabled?() do
      resolved_tmpdir = EvoGit.Sandbox.resolve_tmpdir()

      # Select a supported profile before running the user's command.
      profile = effective_profile(cwd, repo_root)

      {exec, exec_args} =
        if Nix.active?() do
          Nix.wrap_command(executable, args)
        else
          {executable, args}
        end

      # Inject LC_ALL=C and GIT_EDITOR=<true path> for git commands so that
      # automated operations that may open an interactive editor (e.g.
      # `git merge --continue`, rebase, am, commit) never block. Detection
      # uses the ORIGINAL executable param (before nix/bash wrapping).
      git_env =
        if EvoGit.GitEnv.git_command?(executable),
          do: EvoGit.GitEnv.git_env_list(cwd),
          else: []

      # Wrap in bash with stdin redirected from /dev/null so commands like rg
      # that read stdin on missing args get immediate EOF instead of hanging.
      wrapped_cmd = Helpers.build_shell_command(exec, exec_args) <> " < /dev/null"

      # sandbox-exec -p <profile> -- bash -c <wrapped_cmd>
      sandbox_exec(profile, "bash", ["-c", wrapped_cmd], cwd, resolved_tmpdir, git_env)
    else
      # Disabled path: wrap in bash with stdin redirect from /dev/null. The
      # managed per-task tmpdir (when installed) is exported as
      # TMPDIR/TMP/TEMP — see `Helpers.temp_env_vars/0`.
      git_env =
        if EvoGit.GitEnv.git_command?(executable),
          do: EvoGit.GitEnv.git_env_list(cwd),
          else: []

      wrapped_cmd = Helpers.build_shell_command(executable, args) <> " < /dev/null"

      System.cmd("bash", ["-c", wrapped_cmd],
        cd: cwd,
        stderr_to_stdout: true,
        env: git_env ++ Helpers.temp_env_vars()
      )
    end
  end

  # Shared by foreground calls and Background: probe with `true` before
  # starting user work, then reuse the supported profile for this VM.
  @doc false
  def effective_profile(cwd, repo_root \\ nil) do
    profile = generate_profile(cwd, repo_root)

    case :persistent_term.get(@process_limit_rejected_key, :unknown) do
      true -> strip_process_limit(profile)
      false -> profile
      :unknown -> probe_profile(profile, cwd)
    end
  end

  defp probe_profile(profile, cwd) do
    tmpdir = EvoGit.Sandbox.resolve_tmpdir()

    case sandbox_exec(profile, "/usr/bin/true", [], cwd, tmpdir, []) do
      {_, 0} ->
        :persistent_term.put(@process_limit_rejected_key, false)
        profile

      _ ->
        stripped = strip_process_limit(profile)

        case sandbox_exec(stripped, "/usr/bin/true", [], cwd, tmpdir, []) do
          {_, 0} ->
            :persistent_term.put(@process_limit_rejected_key, true)

            Logger.warning(
              "sandbox-exec rejected the (limit ...) rule; running with the process-count limit disabled"
            )

            stripped

          _ ->
            profile
        end
    end
  end

  # Generate an SBPL (Sandbox Policy Language) profile.
  #
  # Policy: READS are allow-by-default at the ROOT — `(allow file-read*
  # (subpath "/"))` makes the whole filesystem readable so agents can use
  # user-installed tools anywhere (Homebrew /opt/homebrew, Intel /usr/local,
  # /Applications, custom /opt installs, nix, asdf/mise). The previous
  # enumerated system-read allow-list proved unmaintainable (the
  # /opt/homebrew miss already broke Apple Silicon Homebrew git; ANY
  # user-installed tool outside the enumerated prefixes was unreadable).
  # Protection comes from the deny-read list below — in Apple's SBPL, deny
  # rules take precedence over allow rules, so the deny-read list (home-based
  # credential stores + system-level sensitive locations, both /etc↔/private/etc
  # and /var↔/private/var spellings) wins over the root read allow. WRITES
  # are deny-by-default: restricted to the worktree, tmp paths, genesis dirs,
  # and package-manager/toolchain cache dirs, with deny-write rules for
  # sensitive dirs as defense in depth. The git metadata rule resolves
  # linked-worktree `gitdir:` pointers so the per-worktree metadata dir
  # (objects/refs/index) is covered even when the caller passes a worktree
  # root or nil repo_root.
  #
  # NOTE: all comments are kept in Elixir source (not emitted into the
  # profile string) because `#` comment support in sandbox-exec could not be
  # validated here; the emitted profile is pure SBPL rules.
  @doc false
  def generate_profile(cwd, repo_root \\ nil) when is_binary(cwd) do
    home = System.user_home!()

    # --- Filesystem READ rules ---
    #
    # Reads are allow-by-default at the ROOT: `(allow file-read* (subpath "/"))`
    # makes the entire filesystem readable so agents can use user-installed
    # tools anywhere (Homebrew /opt/homebrew, Intel /usr/local, /Applications,
    # custom /opt installs, nix, asdf/mise). This replaces the old enumerated
    # system_read_paths allow-list — enumerating every legitimate tool path
    # proved unmaintainable (the /opt/homebrew miss already broke Apple
    # Silicon Homebrew git). Protection for sensitive locations comes from
    # the deny-read rules below (SBPL deny precedence: denies win over
    # allows).
    system_read_rule = ~s{(allow file-read* (subpath "/"))}

    # Belt-and-suspenders: the specific read rules below (nix reads, home,
    # host $TMPDIR, vendored git, file-read-metadata, ssh literals) are
    # REDUNDANT under the root-wide read allow but intentionally KEPT — a
    # safety net if `(subpath "/")` behaves unexpectedly on some macOS
    # (CI is Linux, so real-macOS validation of the root rule is pending).

    # Nix store/var: read (toolchain binaries) + write (build outputs) —
    # only when nix is enabled.
    nix_rules =
      if Nix.enabled?() do
        nix_paths = ["/nix/store", "/nix/var"]

        nix_paths
        |> Enum.flat_map(fn path ->
          [
            ~s{(allow file-read* (subpath "#{path}"))},
            ~s{(allow file-write* (subpath "#{path}"))}
          ]
        end)
        |> Enum.join("\n    ")
      else
        ""
      end

    # Repo access: the worktree (cwd) plus the git metadata dir. cwd is
    # emitted here with the read allow; the write allow follows below. The
    # metadata dir is resolved via `Helpers.git_metadata_dir/2`, which follows
    # linked-worktree `gitdir:` pointer files so the common git dir is
    # covered even when the caller passes a worktree root or nil repo_root.
    git_metadata_rule =
      case Helpers.git_metadata_dir(cwd, repo_root) do
        nil ->
          ""

        git_path ->
          ~s{(allow file-read* (subpath "#{git_path}"))\n    (allow file-write* (subpath "#{git_path}"))}
      end

    # Vendored git (desktop bundle): when git is NOT on PATH,
    # `Executable.resolve("git")` returns the absolute path of the bundled
    # binary (`<app_dir>/priv/vendor/macos-<arch>/git`). An explicit read
    # rule for the binary's dirname is emitted (vendored binaries are
    # self-contained — the dirname subpath is the minimal targeted rule).
    # Redundant under the root-wide read allow but KEPT as belt-and-suspenders.
    # When git IS on PATH, resolve returns the bare name "git" and no rule is
    # emitted.
    git_binary_read_rule =
      case EvoGit.Executable.resolve("git") do
        "git" ->
          ""

        binary when is_binary(binary) ->
          ~s{(allow file-read* (subpath "#{Path.dirname(binary)}"))}
      end

    git_rules =
      [git_metadata_rule, git_binary_read_rule]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n    ")

    # Tmp paths: read-write — processes create temp files and read them back.
    # Seatbelt matches the resolved paths behind macOS's /tmp and /var aliases.
    tmp_paths = Enum.uniq(Platform.tmp_paths() ++ ["/private/tmp", "/private/var/tmp"])

    tmp_rules =
      Enum.map_join(tmp_paths, "\n    ", fn path ->
        ~s{(allow file-read* (subpath "#{path}"))\n    (allow file-write* (subpath "#{path}"))}
      end)

    # Managed per-task tmpdir (when installed on the calling process): the
    # runtime injects this as the sandbox TMPDIR, so it must be granted BOTH
    # read and write access. It is an ADDITIONAL path — the system tmp dirs
    # (tmp_rules above) stay writable regardless. Evaluates to "" when unset,
    # mirroring the empty-group pattern used by git_rules/nix_rules.
    task_tmpdir_rules =
      Enum.map_join(List.wrap(Helpers.task_tmpdir_path()), "\n    ", fn path ->
        ~s{(allow file-read* (subpath "#{path}"))\n    (allow file-write* (subpath "#{path}"))}
      end)

    # Genesis config/data dirs (e.g. `~/Library/Application Support/genesis`
    # on macOS — NOT under /tmp or the repo): the runtime reads and writes
    # config, credentials, state, and logs there.
    genesis_rw_rules =
      [Platform.config_dir(), Platform.data_dir()]
      |> Enum.map_join("\n    ", fn path ->
        ~s{(allow file-read* (subpath "#{path}"))\n    (allow file-write* (subpath "#{path}"))}
      end)

    # Home reads: allow the whole home, then deny-read the sensitive dirs.
    # Deny rules take precedence over allow rules in SBPL, so the deny-read
    # list below wins over this allow.
    home_read_rule = ~s{(allow file-read* (subpath "#{home}"))}

    sensitive_read_dirs = [
      ".ssh",
      ".gnupg",
      ".aws",
      ".kube",
      ".config/sops",
      ".git-credentials",
      ".netrc",
      ".password-store",
      "Library/Keychains",
      # Additional credential stores (parity with the Linux backend's
      # InaccessiblePaths, which already includes .npmrc).
      ".npmrc",
      ".pypirc",
      ".docker",
      ".gem"
    ]

    sensitive_read_rules =
      Enum.map_join(sensitive_read_dirs, "\n    ", fn dir ->
        path = Path.join(home, dir)
        ~s{(deny file-read* (subpath "#{path}"))}
      end)

    # System-level sensitive locations (defense in depth): under the
    # root-wide read allow these must be explicitly denied. Most are
    # root-only-readable anyway, but the deny list guarantees it even if
    # file permissions are relaxed. Both symlink spellings are covered
    # (/etc ↔ /private/etc and /var ↔ /private/var), mirroring the pattern
    # of the home-based list.
    system_sensitive_read_paths = [
      "/etc/ssh",
      "/private/etc/ssh",
      "/var/root",
      "/private/var/root",
      "/etc/master.passwd",
      "/private/etc/master.passwd",
      "/var/db/dslocal",
      "/private/var/db/dslocal",
      "/var/db/Keychains",
      "/private/var/db/Keychains"
    ]

    system_sensitive_read_rules =
      Enum.map_join(system_sensitive_read_paths, "\n    ", fn path ->
        ~s{(deny file-read* (subpath "#{path}"))}
      end)

    # SSH host verification: `git fetch/push` over SSH must read known_hosts
    # and ssh config to verify the server. Private keys stay unreadable by
    # design — key-based auth over SSH requires ssh-agent (`SSH_AUTH_SOCK`),
    # which never exposes key material to the sandboxed process.
    ssh_literal_rules =
      Enum.map_join(
        [Path.join(home, ".ssh/known_hosts"), Path.join(home, ".ssh/config")],
        "\n    ",
        fn path -> ~s{(allow file-read-data (literal "#{path}"))} end
      )

    # Host $TMPDIR read: on macOS the per-user tmp dir is `/var/folders/...`,
    # NOT under /tmp. The skills executor and other callers write temp files
    # (e.g. skill scripts) to `System.tmp_dir!()` BEFORE invoking the
    # sandbox; with default-deny those files must still be readable inside.
    # Skipped when TMPDIR is unset.
    host_tmpdir_rule =
      case System.get_env("TMPDIR") do
        nil -> ""
        "" -> ""
        dir -> ~s{(allow file-read* (subpath "#{dir}"))}
      end

    # stat/ls/glob on arbitrary paths (e.g. PATH probing) under default-deny.
    file_read_metadata_rule = "(allow file-read-metadata)"

    # --- Filesystem WRITE rules ---

    # Build-cache dirs: package managers and toolchains (`mix deps.get`,
    # `npm install`, `cargo build`) must write their caches — these are core
    # agent workflows. User-configurable via `[sandbox] write_paths`: nil
    # (unset) → the built-in default cache-dir list; set (even `[]`) → the
    # user's list REPLACES the default cache-dir list (only these cache-dir
    # write rules; every other profile group is untouched). Structural paths
    # (cwd, tmp, nix, repo .git, genesis dirs) are always granted elsewhere in
    # the profile — they are not part of the user-configurable list.
    write_paths =
      Helpers.resolve_write_paths(
        EvoGit.Config.resolve([:sandbox, :write_paths]),
        @default_cache_dirs,
        home
      )

    cache_rw_rules =
      Enum.map_join(write_paths, "\n    ", fn path ->
        ~s{(allow file-write* (subpath "#{path}"))}
      end)

    # Sensitive dirs: deny WRITE too (defense in depth — reads are already
    # blocked by the deny-read rules above).
    sensitive_write_dirs = [
      ".ssh",
      ".gnupg",
      ".aws",
      ".kube",
      ".config/sops",
      ".npmrc",
      ".git-credentials",
      ".netrc"
    ]

    sensitive_write_rules =
      Enum.map_join(sensitive_write_dirs, "\n    ", fn dir ->
        path = Path.join(home, dir)
        ~s{(deny file-write* (subpath "#{path}"))}
      end)

    # --- Assembly (order matters for readability; SBPL deny precedence is
    # what makes the deny-read list win over the root read allow) ---
    #
    # Network stays default-allow: agents legitimately run `git fetch/push`,
    # `mix deps.get`, `curl`, and web tools; default-deny network breaks core
    # workflows. The primary boundary is the tightened filesystem + process
    # limits. Future extension point: a `[sandbox] network_mode = "allow" |
    # "deny"` TOML key (belongs in config/schema/) could gate the
    # `(allow network*)` rule below.
    #
    # Real-macOS validation warranted: `sandbox-exec -p` acceptance of the
    # root-wide `(allow file-read* (subpath "/"))` rule and the full profile
    # — see report.
    """
    (version 1)
    (deny default)

    #{system_read_rule}
    #{nix_rules}
    (allow file-read* (subpath "#{cwd}"))
    (allow file-write* (subpath "#{cwd}"))
    #{git_rules}
    #{tmp_rules}
    #{task_tmpdir_rules}
    #{genesis_rw_rules}
    #{home_read_rule}
    #{sensitive_read_rules}
    #{system_sensitive_read_rules}
    #{ssh_literal_rules}
    #{host_tmpdir_rule}
    #{file_read_metadata_rule}
    #{cache_rw_rules}
    (allow file-write-data (literal "/dev/null"))
    (allow file-write-data (literal "/dev/dtracehelper"))
    #{sensitive_write_rules}
    (limit number #{@max_processes})
    (allow process-exec)
    (allow process-fork)
    (allow network*)
    (allow mach-lookup)
    (allow sysctl-read)
    (allow process-info*)
    (allow signal)
    (allow ipc-posix-sem)
    (allow ipc-posix-shm)
    """
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # The compatibility probe removes only the process-count rule.
  defp strip_process_limit(profile) do
    profile
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "(limit "))
    |> Enum.join("\n")
  end

  # sandbox-exec -p <profile> -- <exec> <args> (shared by the run/4 and
  # run_with_partial/6 enabled paths).
  defp sandbox_exec(profile, exec, exec_args, cwd, tmpdir, git_env) do
    System.cmd("sandbox-exec", ["-p", profile, "--", exec | exec_args],
      cd: cwd,
      stderr_to_stdout: true,
      env: [{"TMPDIR", tmpdir} | git_env]
    )
  end

  @doc """
  Runs a command with timeout, recovering partial output on timeout via temp-file redirection.

  Unlike `run/4` which uses blocking `System.cmd/3` and loses all output on timeout,
  this function redirects stdout/stderr to a temp file. If the timeout fires, the
  partial output written so far can still be read from the temp file.

  Returns:
    * `{:ok, output, exit_code}` — command completed within timeout
    * `{:timeout, partial_output}` — command timed out; partial_output may be empty
  """
  @spec run_with_partial(
          String.t(),
          String.t(),
          [String.t()],
          String.t() | nil,
          pos_integer(),
          integer() | nil
        ) ::
          {:ok, String.t(), non_neg_integer()} | {:timeout, String.t()}
  def run_with_partial(cwd, executable, args \\ [], repo_root \\ nil, timeout, max_bytes \\ nil)
      when is_list(args) and is_integer(timeout) and timeout > 0 do
    tmpfile = Helpers.partial_output_tmpfile()

    wrapped_cmd = Helpers.build_redirected_command(executable, args, tmpfile)

    # Detect git on the ORIGINAL executable (before we wrap it in bash)
    is_git = EvoGit.GitEnv.git_command?(executable)

    if enabled?() do
      resolved_tmpdir = EvoGit.Sandbox.resolve_tmpdir()
      profile = effective_profile(cwd, repo_root)

      {exec, exec_args} =
        if Nix.active?() do
          Nix.wrap_command("bash", ["-c", wrapped_cmd])
        else
          {"bash", ["-c", wrapped_cmd]}
        end

      git_env = if is_git, do: EvoGit.GitEnv.git_env_list(cwd), else: []

      task =
        Task.async(fn ->
          sandbox_exec(profile, exec, exec_args, cwd, resolved_tmpdir, git_env)
        end)

      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {output, exit_code}} ->
          content = Helpers.command_output(tmpfile, output, max_bytes)
          {:ok, content, exit_code}

        nil ->
          partial = Helpers.read_tempfile(tmpfile, max_bytes)
          {:timeout, partial <> "\n[TRUNCATED due to timeout]"}
      end
    else
      # Non-sandbox path: no nix wrapping (consistent with run/4 disabled path).
      # The managed per-task tmpdir (when installed) rides along via
      # `Helpers.temp_env_vars/0`.
      git_env =
        if(is_git, do: EvoGit.GitEnv.git_env_list(cwd), else: []) ++ Helpers.temp_env_vars()

      Helpers.run_task_with_partial(
        "bash",
        ["-c", wrapped_cmd],
        cwd,
        git_env,
        timeout,
        tmpfile,
        max_bytes
      )
    end
  end
end
