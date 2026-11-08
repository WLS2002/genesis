defmodule EvoGit.AgentScheduler.WorktreeRetention do
  @moduledoc """
  Keeps unfinished worktrees and their only commit references recoverable.
  Recovery descriptors live beside the workers directory, so they survive a
  runtime restart without changing Git's worktree registration or user files.
  """
  alias EvoGit.Adapters.Git

  def disposition(path, repo, branch) do
    cond do
      not File.exists?(path) ->
        branch_disposition(repo, branch)

      not File.regular?(Path.join(path, ".git")) ->
        {:retain, "unrecognized_worktree"}

      true ->
        case Git.status(path) do
          {:ok, ""} -> branch_disposition(repo, branch)
          {:ok, _} -> {:retain, "uncommitted_changes"}
          _ -> {:retain, "git_status_unavailable"}
        end
    end
  end

  def record(repo, path, branch, meta) do
    entry =
      Map.merge(
        %{"path" => path, "branch" => branch, "repo_root" => repo},
        Map.new(meta, fn {k, v} -> {to_string(k), v} end)
      )

    file = descriptor(repo, path)

    with :ok <- File.mkdir_p(Path.dirname(file)),
         :ok <- File.write(file <> ".tmp", Jason.encode!(entry)),
         :ok <- File.rename(file <> ".tmp", file),
         do: :ok
  end

  def retain(repo, path, branch, reason) do
    meta =
      case File.read(descriptor(repo, path)) do
        {:ok, body} ->
          case Jason.decode(body) do
            {:ok, map} when is_map(map) -> map
            _ -> %{}
          end

        _ ->
          %{}
      end

    head =
      case Git.rev_parse(path) do
        {:ok, value} -> value
        _ -> nil
      end

    record(
      repo,
      path,
      branch,
      Map.merge(meta, %{"reason" => reason, "head" => head, "retained" => true})
    )
  end

  def forget(repo, path), do: File.rm(descriptor(repo, path))

  def list(repo, task_id \\ nil) do
    repo
    |> Path.join(".genesis/recovery/*.json")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      with {:ok, body} <- File.read(file),
           {:ok, entry} when is_map(entry) <- Jason.decode(body),
           true <- is_nil(task_id) or entry["task_id"] == task_id,
           path when is_binary(path) <- entry["path"],
           true <- File.dir?(path) do
        [entry]
      else
        _ -> []
      end
    end)
    |> Enum.take(100)
  end

  defp branch_disposition(repo, branch) do
    case Git.run(["for-each-ref", "--format=%(objectname)", "refs/heads/" <> branch], repo) do
      {:error, _} ->
        {:retain, "git_refs_unavailable"}

      {:ok, ""} ->
        :discard

      {:ok, heads} ->
        head = heads |> String.split("\n", trim: true) |> hd()

        case Git.run(
               [
                 "for-each-ref",
                 "--contains",
                 head,
                 "--format=%(refname)",
                 "refs/heads",
                 "refs/genesis/archive"
               ],
               repo
             ) do
          {:ok, refs} ->
            durable =
              refs
              |> String.split("\n", trim: true)
              |> Enum.any?(fn ref ->
                not String.starts_with?(ref, "refs/heads/evogit-agent-")
              end)

            if durable, do: :discard, else: {:retain, "unpublished_commits"}

          _ ->
            {:retain, "git_refs_unavailable"}
        end
    end
  end

  defp descriptor(repo, path) do
    key = :crypto.hash(:sha256, path) |> Base.encode16(case: :lower)
    Path.join([repo, ".genesis/recovery", key <> ".json"])
  end
end
