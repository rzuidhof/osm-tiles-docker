# Perform sed substitutions for `renderd.conf`
s/;socketname=/socketname=/
s/plugins_dir=\/usr\/lib\/mapnik\/input/plugins_dir=\/usr\/lib\/mapnik\/3.0\/input/
s/\(font_dir=\/usr\/share\/fonts\/truetype\)/\1\/ttf-dejavu/
s/XML=.*/XML=\/home\/openstreetmap-carto\/style.xml/
s/HOST=tile.openstreetmap.org/HOST=localhost/
s/;\*\*/;xxx=\*\*/
