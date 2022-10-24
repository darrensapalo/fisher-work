# This allows you to remove fish_user_paths value by selecting the path
function fish-remove-path
    set -l path (echo $fish_user_paths | tr " " "\n" | nl | fzf | awk '{print $1}')
    echo "Deleted on fish_user_paths:" $fish_user_paths[$path]
    set --erase --universal fish_user_paths[$path]
end
