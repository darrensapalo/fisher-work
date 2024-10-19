function docker-logs
    set -l container_id (docker ps --format '{{.ID}} - {{.Names}}' | fzf --height 40% --reverse | awk '{print $1}')
    if test -n "$container_id"
        docker logs -f $container_id
    else
        echo "No container selected."
    end
end