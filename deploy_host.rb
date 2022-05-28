#!/usr/bin/env ruby

require 'erb'
require 'etc'
require 'securerandom'
require 'net/http'

# based originally on my
# https://thomaspowell.com/2017/07/03/migrating-wordpress-dreamhost-linode/
# post

def reload_apache
  `service apache2 reload`
end

DOMAIN=ARGV[0]
USER=ARGV[1]
etc_passwd=Etc.getpwnam(USER)

`sudo apt-get install -y apache2 mysql-client mysql-server`

http_template=<<-HTTP_TEMPLATE
<Directory /var/www/html/<%= DOMAIN %>/public_html>
        Require all granted
</Directory>
<VirtualHost *:80>
        ServerName <%= DOMAIN %>
        ServerAlias www.<%= DOMAIN %>
        ServerAdmin webmaster@<%= DOMAIN %>
        DocumentRoot /var/www/html/<%= DOMAIN %>/public_html

        ErrorLog /var/www/html/<%= DOMAIN %>/logs/error.log
        CustomLog /var/www/html/<%= DOMAIN %>/logs/access.log combined
</VirtualHost>
HTTP_TEMPLATE

https_template=<<-HTTPS_TEMPLATE
<Directory /var/www/html/<%= DOMAIN %>/public_html>
        Require all granted
</Directory>
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
conf_file=ERB.new(http_template)
conf_filename=File.join('/etc/apache2/sites-available', "#{DOMAIN}.conf")
File.write(conf_filename, conf_file.result)

`a2ensite #{DOMAIN}`

reload_apache

def remodown(perms, etc_passwd, filepath)
  File.chmod(perms, filepath)
  File.chown(etc_passwd.uid, etc_passwd.gid, filepath)
end

remodown(0644, etc_passwd, conf_filename)

# Create subdirs and set permissions
[
  File.join('/var/www/html/', DOMAIN),
  File.join('/var/www/html/', DOMAIN, 'logs'),
  File.join('/var/www/html/', DOMAIN, 'public_html')
].each do |dir_path|
  Dir.mkdir(dir_path) unless Dir.exists?(dir_path)
  remodown(0755, etc_passwd, dir_path)
end



# set up a db
database_name="wp_#{DOMAIN.gsub(/\./, '_')}"
username=DOMAIN.gsub(/\./,'')
password=SecureRandom.base64(20)
db_string=<<DBSTRING
CREATE DATABASE #{database_name};
CREATE USER '#{username}' IDENTIFIED BY '#{password}';
GRANT ALL PRIVILEGES ON #{database_name}.* TO '#{username}';
DBSTRING


mysql_invoke_string=ENV['MYSQLPASSWORD'] ? "mysql -u root -p'#{ENV['MYSQLPASSWORD']}'" : "mysql -u root"

# need to either pass the password or change to trusted root?
# pass the password with mysql -pP455w0rd (no space between)
IO.popen(mysql_invoke_string, mode="w+") do |io|
  io.puts db_string
  io.close_write
  puts io.read
end

public_html=File.join('/var/www/html', DOMAIN, 'public_html')

`
  cd #{public_html}
  wget https://wordpress.org/latest.tar.gz
  # curl https://wordpress.org/latest.tar.gz --output latest.tar.gz
  tar zxvf latest.tar.gz
  cd wordpress
  mv * ..
  cd ..
  rm -rf wordpress
`

config_sample=File.open(File.join(public_html, 'wp-config-sample.php')).read

def set_secrets(string, key_name, secret)
  string.gsub(
    /'#{key_name}',\s*'.*'/,
    "'#{key_name}', '#{secret}'"
  )
end

config = set_secrets(config, 'DB_NAME', database_name)
config = set_secrets(config, 'DB_USER', username)
config = set_secrets(config, 'DB_PASSWORD', password)

keys=%w(AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT)
config = keys.inject(config) do |config, key|
  set_secrets(config, key, SecureRandom::hex(16))
end

File.open(File.join(public_html,'wp-config.php'), 'w') do |f|
  f.puts config
end

letsencryptupdate='/usr/local/sbin/letsencryptupdate.sh'

`./letsencrypt-auto certonly -d #{DOMAIN}`

conf_file=ERB.new(https_template)
conf_filename=File.join('/etc/apache2/sites-available', "#{DOMAIN}.conf")
File.write(conf_filename, conf_file.result)

reload_apache


lines=File.open(letsencryptupdate, 'r').readlines
lines.insert(-2, "/opt/letsencrypt/letsencrypt-auto certonly --quiet --apache --renew-by-default -d #{DOMAIN} >> /var/log/letsencrypt/letsencrypt-auto-update.log")

FileUtils.copy(letsencryptupdate, "#{letsencryptupdate}.#{$$}")

File.open(letsencryptupdate, 'w') do |f|
  lines.each { |line| f.puts line }
end

reload_apache
