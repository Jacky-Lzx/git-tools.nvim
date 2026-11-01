vim.opt.rtp:prepend(vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd())
local browse = require("git_tools.browse")
local remote = assert(browse.remote("git@github.com:owner/project.git"))
assert(remote.host == "github.com" and remote.path == "owner/project")
assert(
  browse.url(remote, "abc", "dir/a #中.txt", { range = { 8, 3 } })
    == "https://github.com/owner/project/blob/abc/dir/a%20%23%E4%B8%AD.txt#L3-L8"
)
remote = assert(browse.remote("ssh://git@gitlab.com:2222/group/sub/project.git"))
assert(
  browse.url(remote, "feat/x", "x", { permalink = false, range = { 3, 3 } })
    == "https://gitlab.com/group/sub/project/-/blob/feat%2Fx/x#L3"
)
remote = assert(browse.remote("https://token:secret@bitbucket.org/owner/project.git"))
assert(
  browse.url(remote, "abc", "x", { range = { 3, 8 } }) == "https://bitbucket.org/owner/project/src/abc/x#lines-3:8"
)
assert(browse.url(remote, "abc", nil, { commit = true }) == "https://bitbucket.org/owner/project/commits/abc")
assert(browse.url({ host = "private.example", path = "o/r" }, "abc", "x") == nil)
assert(
  browse.url({ host = "private.example", path = "o/r" }, "abc", "x", { provider = "github" })
    == "https://private.example/o/r/blob/abc/x"
)
assert(not browse.remote("/local/repo"))
print("git browse: remote parsing, encoding, line ranges, providers and credential removal passed")
vim.cmd("qa!")
