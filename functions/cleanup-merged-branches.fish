# This removes branches merged to master from your local machine.
#
# Very handy when you'd like to clean up feature/bugfix branches on your local machine, 
# after they have been merged to master.
#
# See article: https://devconnected.com/how-to-clean-up-git-branches/
function cleanup-merged-branches  
  # Make sure you are in master before doing this, otherwise git branch
  # will not return expected values.

  # Step 1: retrieve all branches merged within the current branch (assuming it is master)
  # Step 2: Fuzzy find which branch you want to remove
  # Step 3: use stream editor to remove whitespaces globally from the text
  # Step 4: Apply `git branch -D <BRANCH_NAME>`
	git branch -D (git branch --merged | fzf | sed -e 's/ //g')
end
