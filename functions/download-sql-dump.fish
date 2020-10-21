# This allows you to download an sql dump from a local pgadmin instance
# that may potentially be connecting to external database.
#
# It relies on fzf for an easier way of selecting files to download.
#
# This expects that the pgadmin
function download-sql-dump
	set -l DOWNLOAD_FILE (docker exec pgadmin ls /var/lib/pgadmin/storage/darren.sapalo_gmail.com/ | fzf)
	docker cp pgadmin:/var/lib/pgadmin/storage/darren.sapalo_gmail.com/$DOWNLOAD_FILE ./$DOWNLOAD_FILE
end
