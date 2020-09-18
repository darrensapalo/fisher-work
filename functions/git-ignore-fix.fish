# This fixes the git-ignore, when some files which should be untracked
# are still detected by the git repository.
#
# See article: https://stackoverflow.com/questions/11451535/gitignore-is-ignored-by-git
function git-ignore-fix
	git rm -r --cached . 
	git add . 
	git commit -m ".gitignore fix"
end
