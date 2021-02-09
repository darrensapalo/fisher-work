# Sometimes, my chromium browser gets weird monospace fonts on Ubuntu. 
# I fix it by restarting chromium.

function restart-chrome -d "kills chrome and then restarts it"; 
  for PID in (pidof chrome | sed 's/ /\n/g'); 
    kill $PID; 
  end; 
  chromium & disown; 
end;
