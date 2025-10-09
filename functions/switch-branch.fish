# Interactive branch switcher with preview
#
# Shows local branches with last updated date and allows you to switch to a branch
# using an interactive fuzzy finder with commit history preview.
#
# Usage:
#   switch-branch       # Show local branches only
#   switch-branch all   # Show all branches including remotes
function switch-branch
  set show_all $argv[1]
  
  # Step 1: Get branches and format with details
  # Format: branch_name | last_commit_date
  set formatted_branches (
    if test "$show_all" = "all"
      git branch --all | grep -v 'HEAD'
    else
      git branch
    end | \
    sed 's/^[[:space:]*]*//' | \
    sed 's/^remotes\///' | \
    sort -u | \
    while read branch
      if test -n "$branch"
        set commit_date (git log -1 --format=%ci "$branch" 2>/dev/null | cut -d' ' -f1)
        if test -n "$commit_date"
          printf "%-50s  %s\n" "$branch" "$commit_date"
        end
      end
    end)
  
  # Step 2: Use fzf to select branch with formatted display
  set header_text "Branch                                              Date"
  if test "$show_all" = "all"
    set header_text "$header_text (all branches)"
  else
    set header_text "$header_text (local branches)"
  end
  
  set selected_branch (printf "%s\n" $formatted_branches | \
    fzf --header="$header_text" \
        --header-lines=0 \
        --preview='git log --oneline --graph --color=always {1} -10' \
        --preview-window=right:50% | \
    awk '{print $1}')
  
  if test -n "$selected_branch"
    # Remove remote prefix if present (e.g., origin/feature -> feature)
    set branch_name (echo $selected_branch | sed 's/^origin\///')
    git switch $branch_name
  end
end
