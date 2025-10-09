# This removes branches merged to master from your local machine.
#
# Very handy when you'd like to clean up feature/bugfix branches on your local machine, 
# after they have been merged to master.
#
# See article: https://devconnected.com/how-to-clean-up-git-branches/
function cleanup-merged-branches  
  # Make sure you are in master before doing this, otherwise git branch
  # will not return expected values.

  # Step 1: Get all merged branches and format with details
  # Format: branch_name | last_commit_date
  set formatted_branches (git branch --merged | \
    grep -v '^\*' | \
    sed 's/^[[:space:]]*//' | \
    while read branch
      set commit_date (git log -1 --format=%ci $branch 2>/dev/null | cut -d' ' -f1)
      printf "%-50s  %s\n" "$branch" "$commit_date"
    end)
  
  # Step 2: Use fzf to select branch with formatted display
  # Step 3: Extract just the branch name (first column)
  # Step 4: Delete the selected branch
  set selected_branch (printf "%s\n" $formatted_branches | \
    fzf --header="Branch                                              Date" \
        --header-lines=0 \
        --preview='git log --oneline --graph --color=always {1} -10' \
        --preview-window=right:50% | \
    awk '{print $1}')
  
  if test -n "$selected_branch"
    git branch -D $selected_branch
  end
end
