/****

Single-Sign-On Settings
----------------------------

This file should be copied to /opt/fileago/sso/ folder, and configured
correctly for SSO to work.

Settings that needs to be changed are marked as 'TO CHANGE'.


Certificates are necessary for secure communication with IdP:

1. Generate a cert/key pair for use in service provider side (replace 'localhost'
   with the hostname of the FileAgo server).

# cd /opt/fileago/sso/
# openssl req -newkey rsa:2048 -nodes -keyout server.key -x509 -days 3650 \ 
  -out server.crt -subj "/C=IN/ST=Maharashtra/L=Mumbai/O=FileAgo/CN=localhost"

2. Download SAML Signing Certificate from identity provider side, and save it
   as /opt/fileago/sso/idp.pem.

****/



var fs = require('fs');

// Service Provider settings
exports.sp_options = {

  // TO CHANGE: set correct hostname for the server
  audience: "https://localhost/saml/metadata",

  // TO CHANGE: set correct hostname for the server
  entity_id: "https://localhost/saml/metadata",

  // TO CHANGE: set correct hostname for the server
  assert_endpoint: "https://localhost/saml/consume",

  private_key: fs.readFileSync("sso/server.key").toString(),
  certificate: fs.readFileSync("sso/server.crt").toString()

};

// Identity Provider settings
exports.idp_options = {

  // TO CHANGE: set identity provider login url (given below is a sample Azure AD login url)
  sso_login_url: "https://login.microsoftonline.com/690bbe32-3d29-4752-afdsfsfasdadsa/saml2",

  // TO CHANGE: set identity provider logout url (given below is Azure AD logout url)
  sso_logout_url: "https://login.microsoftonline.com/common/wsfederation?wa=wsignout1.0",

  certificates: [fs.readFileSync("sso/idp.pem").toString()]

};

