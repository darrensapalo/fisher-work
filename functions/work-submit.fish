function work-submit --description 'Pushes the branch to its corresponding branch in the remote repository.'
	git status | awk '/On branch/ {print $3}' | read -l branch;
git push --set-upstream origin $branch
end
