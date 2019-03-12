v1.2.0 - 11 Mar 2019
---

* Added '15 days' as an option to keep file old revisions
* Added support for Factor Authentication (TOTP based)
* Added support for LDAP/AD authentication
* Download is a new permission option (along with existing r,w,d)
* Public shares also need download permission for file downloads
* FileAgo can now function as a WOPI host
* Completed integration with LibreOffice Online
* Switched from Neo4j to latest OngDB database

v1.1.0 - 30 Nov 2018
---

* Added OPTIONS for /auth endpoint
* Added OPTIONS for /upload/:token endpoint
* Added OPTIONS for /resources/auth/* urls
* Added support for AES-256-GCM encryption of uploaded files
* Fixed many critical bugs related to permissions and user access

v1.0.0 - 23 Oct 2018
---

* First release
