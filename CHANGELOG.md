v1.8.2 - 19 Apr 2022
---

* API endpoint to change last modified timestamp
* Several other minor bugs also fixed


v1.8.1 - 3 Mar 2022
---

* [bugfix] Online license check failure
* [bugfix] Grey in notification emails doesn't show in Outlook
* Support for Collabora lool -> cool migration
* Support for minio as s3 storage
* Making webdrive compatible with FileAgo webdrive app
* Ignore webdav locks by default
* Set 60s timeout for cowboy
* Several other minor bugs also fixed

v1.8.0 - 9 Feb 2021
---

* [bugfix] Fix public share expiry time conflicts
* [bugfix] Allow new version with same file size in wopi
* [bugfix] Report web login for users when sso is enabled
* [bugfix] prevent printing of public shares
* [bugfix] Broken download links for file names with special characters
* Multi-org support
* webdrive LOCK period is now 30 minutes (earlier = 15 mins)
* Backend configurable setting for trash retention period (in days)
* Backend configurable setting for pending incoming share retention period (in days)
* Support for S3 as backend storage for files
* 6 months (180 days) is now a valid duration to preserve old revisions
* Support for external lool/collabora server
* robots.txt - hide everything from search engines
* Save and show last synced time for devices
* Support for cdn/proxy to cache data from S3
* Prevent copy and share-by-copy to incoming of large folders (folder tree with > 500 files)
* Bypass strict token/ip address matching if required
* Support for cloudinit
* Upload file queue limit is now 500 in Web Portal

v1.7.0 - 27 Oct 2020
---

* FileAgo BackupCentral implementation (file backup solution)
* Integration with O365 and Microsoft Online Office Server
* [bugfix] Display correct upload queue limit
* [bugfix] LDAP parse failing with badarg error
* Disable print screen for public shares
* Store and display last login info of users in admin panel
* Admin can export user list as csv from admin panel
* [bugfix] Incorrect file version in WOPI
* Watermark in DocView when accessing read-only documents
* Show disk utilisation in admin panel
* Some other minor bugs also fixed

v1.6.0 - 3 Aug 2020
---

* Single Sign On (SAML) integration
* [bugfix] Cleanup old chunks from tmp folder
* [bugfix] Webdrive fails if & character is found in file/folder names
* Improved performance of cleanup task
* LDAP sync interval is now constant 5 minutes and cannot be changed by user
* 'encrypt_files' is set true, and cannot be changed by user
* Prevent shell expansion during ldapsearch command execution
* License key is now stored in database itself
* Prevent creation of folders if quota of target owner is exhausted
* Allow/deny list implementation in backend for WebDrive and sharing (UI side tbd)
* Several other minor bugs also fixed

v1.5.0 - 10 Apr 2020
---

* Chat and video integration with Rocket.chat
* Disable printing from browser on public shares
* Accomodate incorrect urls in webdrive endpoint for broken clients
* Add FileAgo version and license API endpoints
* Allow updating license from Admin Panel
* Minor UI enhancements and bugs also fixed

v1.4.1 - 18 Feb 2020
---

* Password protected public shares implementation
* Fixed bug of files reporting incorrect updated time
* Major architecture improvements in WebDrive
* All deleted file revisions are now cleaned up from database
* Maximum number of revisions now limited to 500
* Maximum number of revisions for .slog and .dat files via WebDrive limited to 10
* "Private share create" permission logic applies for copy sharing too
* New config option in internal db: "allow_sharing_with_all_groups"
* Ldap group sync functionality implementation
* Ldap attribute "faDefaultQuota" to override quota value for individual users and groups
* Support to skip WebDrive LOCK checks internally if needed
* "If-None-Match" header support for WebDrive urls
* Fixed bug where WebDrive was listing blocked resources
* WebDrive replies now has cache-control header set to 'no-cache'
* Fixed issues when file end up with multiple revisions having same timestamp
* Some other minor bugs fixed

v1.4.0 - 8 Dec 2019
---

* FileAgo WebDrive (WebDAV) implementation
* Encrypt and Preview manager processes now use different sqlite dbs
* Send custom message in email while creating pubic shares
* Support for usage of 'latest' and 'oldest' in file download url
* File downloads reply now have Content-Length header set
* Various other minor bugs fixed

v1.3.1 - 24 Sep 2019
---

* Fixed bug where chunk creation failed for empty files
* Notification emails now use images hosted at fileago.com
* Fixed bug where API auth was crashing sometimes due to exceptions
* Notification emails now more compatible to email standards

v1.3.0 - 6 Aug 2019
---

* Variable size file chunking algorithm support
* Fixed bug regarding public share emails not getting sent
* Creating new dir returns http 200 with data now, and not 204
* ldapsearch can now do paged searches and fetch all results
* Removed websocket connect/disconnect popup notification
* Fixed bug where files created via WOPI was not respecting disk quota restrictions
* Added support for preview of CAD files
* Added support for sync agent application
* Many minor bugs also fixed

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
