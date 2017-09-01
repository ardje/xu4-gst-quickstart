Transplant backlog recording example into lua-lgi so we can give libsoup commands


Dump all of Gst:
lua -llgi -lpl.pretty -e '_ENV["pl.pretty"].dump(lgi.Gst:_resolve(true))'
