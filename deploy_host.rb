#!/usr/bin/env ruby

require 'erb'
require 'etc'

# based originally on my
# https://thomaspowell.com/2017/07/03/migrating-wordpress-dreamhost-linode/
# post

DOMAIN=ARGV[0]
USER=ARGV[1]
etc_passwd=Etc.getpwnam(USER)


conf_template=<<-TEMPLATE
<Directory /var/www/html/<%= DOMAIN %>/public_html>
  Require all granted
</Directory>

<VirtualHost *:80>
  ServerName <%= DOMAIN %>
  ServerAlias www.<%= DOMAIN %>
  ServerAdmin email@<%= DOMAIN %>
  DocumentRoot /var/www/html/<%= DOMAIN %>/public_html
  ErrorLog /var/www/html/<%= DOMAIN %>/logs/error.log
CustomLog /var/www/html/<%= DOMAIN %>/logs/access.log combined
</VirtualHost>
TEMPLATE

https_template=<<-HTTPS_TEMPLATE
<VirtualHost *:80>
        ServerName <%= DOMAIN %>
        ServerAlias www.<%= DOMAIN %>
        Redirect / https://<%= DOMAIN %>/
</VirtualHost>
<VirtualHost *:443>
        SSLEngine On
        # comment these three lines out
        # sudo apache restart
        # run letsencrypt
        # sudo apache restart (reload seemed to get in a weird state)
        SSLCertificateFile /etc/letsencrypt/live/<%= DOMAIN %>/cert.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/<%= DOMAIN %>/privkey.pem
        SSLCertificateChainFile /etc/letsencrypt/live/<%= DOMAIN %>/chain.pem

        ServerName <%= DOMAIN %>
        ServerAlias www.<%= DOMAIN %>
        ServerAdmin webmaster@<%= DOMAIN %>
        DocumentRoot /var/www/html/<%= DOMAIN %>/public_html


        ErrorLog /var/www/html/<%= DOMAIN %>/logs/error.log
        CustomLog /var/www/html/<%= DOMAIN %>/logs/access.log combined
</VirtualHost>
HTTPS_TEMPLATE


# Set up the virtual host
conf_file=ERB.new(conf_template)
conf_filename=File.join('/var/www/html', "#{DOMAIN}.conf")
File.write(conf_filename, conf_file.result)


def remodown(perms, etc_passwd, filepath)
  File.chmod(perms, filepath)
  File.chown(etc_passwd.uid, etc_passwd.gid, filepath)
end

remodown(0644, etc_passwd, conf_filename)

# Create subdirs and set permissions
[
  File.join('/var/www/html/', DOMAIN),
  File.join('/var/www/html/', DOMAIN, 'logs')
].each do |dir_path|
  Dir.mkdir(dir_path)
  remodown(0755, etc_passwd, dir_path)
end

# set up a db

# CREATE DATABASE wp_example_com;
# CREATE USER 'examplecom' IDENTIFIED BY '!@(87P@ss';
# GRANT ALL PRIVILEGES ON wp_example_com.* TO 'examplecom';
# USE wp_example_com;
# SOURCE example.com.sql;

# change wp-config.php for the DB setup
# // ** MySQL settings – You can get this info from your web host ** //
# /** The name of the database for WordPress */
# define('DB_NAME', 'wp_example_com');
#
# /** MySQL database username */
# define('DB_USER', 'examplecom');
#
# /** MySQL database password */
# define('DB_PASSWORD', '!@(87P@ss');
#
# /** MySQL hostname */
# define('DB_HOST', 'localhost');
#

# Enable the site

`a2ensite #{DOMAIN}`
