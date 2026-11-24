local root = vim.env.GIT_TOOLS_ROOT or vim.fn.getcwd()
vim.opt.runtimepath:prepend(vim.fs.joinpath(root, "..", "base-tools.nvim"))
