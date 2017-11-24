#!/bin/bash

echo "Place SSL certificates if defined"
<% if_p("ssl.certificates") do |certificates| -%>
echo "Placing certs"
<% for cert in certificates -%>
cat > /var/vcap/jobs/nginx/ssl/<%= cert.name %>.crt << EOF
<%= cert.certificate %>
EOF
cat > /var/vcap/jobs/nginx/ssl/<%= cert.name %>.key << EOF
<%= cert.key %>
EOF
<% end -%>
echo "Done"
<% end -%>
