defmodule EvoGit.AgentScheduler.WorktreeRetentionTest do
  use ExUnit.Case, async: false
  alias EvoGit.Adapters.Git
  alias EvoGit.AgentScheduler.WorktreeRetention
  @moduletag :tmp_dir

  setup %{tmp_dir: root} do
    {:ok, _} = Git.init(root)
    File.write!(Path.join(root, "file.txt"), "initial")
    {:ok, _} = Git.add(root, ".")
    {:ok, _} = Git.commit(root, "initial")
    {:ok, head} = Git.rev_parse(root)
    wt = Path.join(root, ".genesis/workers/worker_T1_A1")
    branch = "evogit-agent-T1-A1"
    {:ok, _} = Git.add_worktree(root, wt, head, branch)
    %{root: root, wt: wt, branch: branch}
  end

  test "keeps dirty and untracked work even when HEAD is already reachable", %{
    root: root,
    wt: wt,
    branch: branch
  } do
    File.write!(Path.join(wt, "file.txt"), "unfinished")
    File.write!(Path.join(wt, "new.txt"), "untracked")
    assert {:retain, "uncommitted_changes"} = WorktreeRetention.disposition(wt, root, branch)
    assert File.read!(Path.join(wt, "new.txt")) == "untracked"
  end

  test "keeps clean work with a commit only reachable from its agent branch", %{
    root: root,
    wt: wt,
    branch: branch
  } do
    File.write!(Path.join(wt, "file.txt"), "finished step")
    {:ok, _} = Git.add(wt, ".")
    {:ok, _} = Git.commit(wt, "partial step")
    assert {:retain, "unpublished_commits"} = WorktreeRetention.disposition(wt, root, branch)
    {:ok, head} = Git.rev_parse(wt)
    {:ok, _} = Git.run(["branch", "genesis/agent_saved", head], root)
    assert :discard = WorktreeRetention.disposition(wt, root, branch)
  end

  test "keeps an unreadable or non-worktree directory", %{root: root, branch: branch} do
    other = Path.join(root, "unknown")
    File.mkdir_p!(other)
    assert {:retain, "unrecognized_worktree"} = WorktreeRetention.disposition(other, root, branch)
  end
end
