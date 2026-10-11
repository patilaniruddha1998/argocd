

# FeeJunction DC/DR Failover Flow

How the snap pipeline and the database failover pipeline run end to end: every stage, approval, mail, server, database, Availability Group, file and Nexus upload. Shown for DC to DR; the DR to DC differences are in section 8.

## 1. Landscape

Jenkins runs on the master node; every Ansible run happens on the Linux agent `linux_node_ansible`, which reaches the Windows database servers over Windows Remote Management (port 5985, NTLM) and the Linux application servers over SSH (port 2222).

```mermaid
flowchart LR
  subgraph JEN["Jenkins master"]
    SNAP["Thanos/FeeJunction/snap<br/>Jenkinsfile_snap"]
    DBJ["Thanos/FeeJunction/database_failover<br/>Jenkinsfile_db"]
    OTH["prerequisite · properties · real_services<br/>cron · virtualService · tomcat · waf"]
  end
  subgraph ANS["Ansible node: linux_node_ansible"]
    PB["Playbooks and roles<br/>/opt/jenkinsagent/linux_node_ansible/workspace/<br/>Tools/loadAnsiblePlayBookScripts/Thanos_FeeJunctionDB"]
    CR["Credentials per server and database<br/>/opt/AnsibleWin/IP_DATABASE.yml"]
    TMP["Records and staging<br/>/tmp/sql_backups/ · /tmp/log_shipping_report.csv"]
  end
  subgraph DC["DC site"]
    DCLB["DC load balancer 172.16.7.20:9997"]
    APPDC["app-dc-01 172.16.31.34<br/>app-dc-02 172.16.31.66"]
    DBDC1["db-dc-01 172.16.51.3<br/>primary SQL Server<br/>X:\DB_BACKUPS\Tran\DATABASE"]
    DBDC2["db-dc-02 172.16.51.2<br/>Availability Group partner"]
  end
  subgraph DR["DR site"]
    DRLB["DR load balancer 192.168.2.5:9997"]
    APPDR["app-dr-01 192.168.26.34<br/>app-dr-02 192.168.26.66"]
    DBDR1["db-dr-01 192.168.27.5<br/>goes live after failover<br/>G:\DB_BACKUPS\Tran\DATABASE"]
    DBDR2["db-dr-02 192.168.27.4<br/>stays RESTORING"]
  end
  NEX[("Nexus 172.16.15.34:8081<br/>repository dc-dr-migration")]
  MAIL[["Email Extension mail<br/>DCDR_EMAIL_RECIPIENTS"]]
  WAF{{"Indusface WAF<br/>customer traffic"}}

  SNAP -->|"build, wait"| OTH
  SNAP -->|"build x3, one per database"| DBJ
  SNAP -.->|"stage and final mails"| MAIL
  OTH --> PB
  DBJ --> PB
  DBJ -.->|"curl -k upload of records"| NEX
  PB -->|"WinRM 5985"| DBDC1
  PB -->|"WinRM 5985"| DBDR1
  PB -->|"WinRM 5985"| DBDR2
  PB -->|"SSH 2222"| APPDC
  PB -->|"SSH 2222"| APPDR
  PB -->|"LB API 9997"| DCLB
  PB -->|"LB API 9997"| DRLB
  DBDC1 -->|"Availability Group"| DBDC2
  DBDC1 -.->|"log shipping: LSCopy pulls, LSRestore applies"| DBDR1
  DBDC1 -.->|"log shipping"| DBDR2
  OTH -->|"waf job"| WAF
  CR --- PB
  TMP --- PB

  classDef site fill:#1d5fbf14,stroke:#1d5fbf,stroke-width:1px
  classDef ext fill:#1f7a4614,stroke:#1f7a46
  class NEX,MAIL,WAF ext
```

| Server                | Address             | Role in DC to DR                                                                                                                   |
|-----------------------|---------------------|------------------------------------------------------------------------------------------------------------------------------------|
| db-dc-01              | 172.16.51.3         | Source SQL Server (first host of `[database_dc]`); backups in `X:\DB_BACKUPS\Tran\DATABASE`, share `\\172.16.51.3\X$\...`          |
| db-dc-02              | 172.16.51.2         | Availability Group partner of db-dc-01; not touched                                                                                |
| db-dr-01              | 192.168.27.5        | Target, brought ONLINE (first host of `[database_dr]`); `G:\DB_BACKUPS\Tran\DATABASE`                                              |
| db-dr-02              | 192.168.27.4        | Target, restored to the same point, stays RESTORING                                                                                |
| app-dc-01 / app-dc-02 | 172.16.31.34 / .66  | Source application servers (SSH 2222); app-dc-02 runs pod 3 (8301)                                                                 |
| app-dr-01 / app-dr-02 | 192.168.26.34 / .66 | Target application servers; app-dr-02 runs pod 3 (8301)                                                                            |
| DC load balancer      | 172.16.7.20:9997    | Real services `FeesJun_31_34_8001`, `_31_34_8101`, `_31_66_8001`, `_31_66_8101`, `_31_66_8301`; virtual service `FeesJunction_gpx` |
| DR load balancer      | 192.168.2.5:9997    | Real services `FeesJun_26_34_8001`, `_26_34_8101`, `_26_66_8001`, `_26_66_8101`, `_26_66_8301`; virtual service `FeesJunction_gpx` |
| Ansible node          | linux_node_ansible  | Runs every playbook; holds credentials, staging and records                                                                        |
| Nexus                 | 172.16.15.34:8081   | Raw repository `dc-dr-migration`, credential `NEXUS_CREDS_ANI`                                                                     |

| Database                     | Availability Group (DC) | Snap parameter (default)                                   |
|------------------------------|-------------------------|------------------------------------------------------------|
| FEESJUNCTIONGENERIC          | `WL_FJ_AG`              | `FAILOVER_FEESJUNCTIONGENERIC` (ticked) · 1st              |
| FEESJUNCTIONGENERICGOVT_LIVE | `WL_FJGOVT_AG`          | `FAILOVER_FEESJUNCTIONGENERICGOVT_LIVE` (not ticked) · 2nd |
| SOCIETY_JUNCTION             | `WL_SJ_AG`              | `FAILOVER_SOCIETY_JUNCTION` (not ticked) · 3rd             |

| Log shipping job               | Server             |
|--------------------------------|--------------------|
| `LSBackup_DATABASE`            | db-dc-01           |
| `LSCopy_SOURCESQL_DATABASE`    | db-dr-01, db-dr-02 |
| `LSRestore_SOURCESQL_DATABASE` | db-dr-01, db-dr-02 |

| Credentials file (Ansible node)             | Used for |
|---------------------------------------------|----------|
| `/opt/AnsibleWin/172.16.51.3_DATABASE.yml`  | db-dc-01 |
| `/opt/AnsibleWin/192.168.27.5_DATABASE.yml` | db-dr-01 |
| `/opt/AnsibleWin/192.168.27.4_DATABASE.yml` | db-dr-02 |

SOURCESQL is the `sql_server` value in the source credentials file; DATABASE is the database being failed over.

## 2. Snap pipeline: Thanos/FeeJunction/snap

Before anything runs, snap reads which databases are ticked (`FAILOVER_FEESJUNCTIONGENERIC` by default) and stops if none is. Unticked databases are not touched and stay on the source site. One click then runs nine stages in order. Two manual gates stop the build for a person: one before anything touches the databases, one before the target site takes traffic. Stop and Start each run four downstream jobs in parallel.

```mermaid
flowchart TD
  A(["Start snap<br/>DIRECTION = DC to DR or DR to DC · JIRA_ID<br/>FAILOVER_FEESJUNCTIONGENERIC (default ticked)<br/>FAILOVER_FEESJUNCTIONGENERICGOVT_LIVE · FAILOVER_SOCIETY_JUNCTION (default not ticked)"]):::start
  SEL{"Any database ticked?"}:::gate
  X0(["STOP: No database selected<br/>nothing changed"]):::bad

  P1["1 Prerequisite<br/>job Thanos/FeeJunction/prerequisite<br/>DIRECTION · ENVIRONMENT=prod_dr · JIRA_ID<br/>a Application servers status<br/>b Port check 8001, 8101, 8301 on DR app servers<br/>c Database servers status<br/>d Application deployment sync<br/>e Properties sync, runs Thanos/FeeJunction/properties if needed<br/>f Properties field sync"]:::stage
  M1>"Mail: Prerequisite result"]:::mail
  X1(["STOP: nothing changed on either site"]):::bad

  P2["2 Check Source Reachability<br/>TCP DC LB 172.16.7.20:9997<br/>TCP app-dc-01 172.16.31.34:2222<br/>TCP app-dc-02 172.16.31.66:2222<br/>unreachable parts are skipped later"]:::stage

  subgraph STOP["3 Stop Services on DC, four jobs in parallel"]
    S1["Thanos/FeeJunction/real_services<br/>SITE=DC ACTION=Disable<br/>SERVICE_NAMES=FeesJun_31_34_8001 ... _31_66_8301"]:::stage
    S2["Thanos/FeeJunction/cron<br/>SITE=application_dc ACTION=stop<br/>LIMIT_HOSTS = reachable servers"]:::stage
    S3["Thanos/FeeJunction/virtualService<br/>SITE=DC ACTION=Disable<br/>FeesJunction_gpx"]:::stage
    S4["Thanos/FeeJunction/tomcat<br/>SITE=application_dc ACTION=stop<br/>LIMIT_HOSTS = reachable servers"]:::stage
  end
  M3>"Mail: Stop Services result table"]:::mail
  R1(["Automatic restore of DC services<br/>same four jobs, ACTION=Enable / start<br/>only what this build stopped"]):::bad

  G1{{"4 DB Failover Approval<br/>approval mail with link<br/>input DbFailoverStartApproval<br/>button: Proceed with DB Failover"}}:::gate

  subgraph DBF["5 DB Failover, only the ticked databases, one after the other"]
    D1["Thanos/FeeJunction/database_failover<br/>DATABASE=FEESJUNCTIONGENERIC (if ticked)<br/>MIGRATION_DIRECTION=dc_to_dr · SOURCE_DOWN_MODE=auto"]:::stage
    D2["same job<br/>DATABASE=FEESJUNCTIONGENERICGOVT_LIVE (if ticked)"]:::stage
    D3["same job<br/>DATABASE=SOCIETY_JUNCTION (if ticked)"]:::stage
    D1 -->|"SUCCESS or UNSTABLE"| D2 -->|"SUCCESS or UNSTABLE"| D3
  end
  M5>"Mail: DB Failover result per database<br/>UNSTABLE = online with DATA LOSS"]:::mail
  X5(["ACTION NEEDED<br/>first non-SUCCESS database stops the stage<br/>remaining databases NOT RUN<br/>no services anywhere, nothing restored automatically"]):::bad

  G2{{"6 Start Services Approval<br/>approval mail with database results<br/>input StartServicesApproval<br/>button: Start Services"}}:::gate
  X6(["Aborted: nothing started on DR<br/>nothing restored on DC"]):::bad

  P7["7 Check Target Reachability<br/>TCP DR LB 192.168.2.5:9997<br/>TCP app-dr-01 192.168.26.34:2222<br/>TCP app-dr-02 192.168.26.66:2222<br/>anything unreachable fails"]:::stage

  subgraph START["8 Start Services on DR, four jobs in parallel"]
    T1["real_services<br/>SITE=DR ACTION=Enable<br/>FeesJun_26_34_8001 ... _26_66_8301"]:::stage
    T2["cron<br/>SITE=application_dr ACTION=start"]:::stage
    T3["virtualService<br/>SITE=DR ACTION=Enable<br/>FeesJunction_gpx"]:::stage
    T4["tomcat<br/>SITE=application_dr ACTION=start"]:::stage
  end
  M8>"Mail: Start Services result table"]:::mail
  U8(["Automatic undo on DR<br/>ACTION=Disable / stop<br/>what this build started"]):::bad

  P9["9 WAF Traffic Switch<br/>job Thanos/FeeJunction/waf<br/>MIGRATION_DIRECTION=DC_TO_DR"]:::stage
  M9>"Mail: WAF result"]:::mail

  F(["post always: Stop, DB, Start and WAF summaries in console<br/>post cleanup: FINAL consolidated mail<br/>every stage, every result table, rollback results"]):::mailend

  A --> SEL
  SEL -->|"yes"| P1
  SEL -->|"no"| X0
  P1 -->|"SUCCESS or UNSTABLE"| P2
  P1 -->|"FAILURE"| X1
  P1 -.-> M1
  P2 --> STOP
  STOP -.-> M3
  STOP -->|"done"| G1
  STOP -->|"failure or abort"| R1
  G1 -->|"approved"| DBF
  G1 -->|"abort"| R1
  DBF -.-> M5
  DBF -->|"all online"| G2
  DBF -->|"failure or abort"| X5
  G2 -->|"approved"| P7
  G2 -->|"abort"| X6
  P7 --> START
  P7 -->|"failure"| X6
  START -.-> M8
  START -->|"done"| P9
  START -->|"failure or abort"| U8
  P9 -.-> M9
  P9 --> F
  R1 --> F
  X5 --> F
  X6 --> F
  U8 --> F
  X1 --> F
  X0 --> F

  classDef start fill:#1d5fbf26,stroke:#1d5fbf,stroke-width:2px
  classDef stage fill:#1d5fbf12,stroke:#1d5fbf
  classDef gate fill:#a35a0018,stroke:#a35a00,stroke-width:2px
  classDef mail fill:#1f7a4618,stroke:#1f7a46
  classDef mailend fill:#1f7a4624,stroke:#1f7a46,stroke-width:2px
  classDef bad fill:#b3261e14,stroke:#b3261e
```

| Stage                       | Downstream job and parameters                                                                                                                       | If it fails or is aborted                                      |
|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------|
| 1 Prerequisite              | `Thanos/FeeJunction/prerequisite` · DIRECTION, ENVIRONMENT (`prod_dr` / `prod_dc`), JIRA_ID. May trigger `Thanos/FeeJunction/properties`.           | Build stops; nothing changed. UNSTABLE continues as a warning. |
| 2 Check Source Reachability | TCP checks from Jenkins, no job                                                                                                                     | Unreachable parts are marked SKIPPED in Stop Services          |
| 3 Stop Services             | `real_services` SITE, ACTION, SERVICE_NAMES · `cron` SITE, ACTION, LIMIT_HOSTS · `virtualService` SITE, ACTION · `tomcat` SITE, ACTION, LIMIT_HOSTS | Restores what this build stopped on the source                 |
| 4 DB Failover Approval      | input `DbFailoverStartApproval`, approver recorded in `DB_APPROVER`                                                                                 | Abort restores the source services                             |
| 5 DB Failover               | `Thanos/FeeJunction/database_failover`, one build per ticked database · MIGRATION_DIRECTION (`dc_to_dr`), DATABASE, SOURCE_DOWN_MODE=auto           | No automatic restore anywhere; ACTION NEEDED in the mails      |
| 6 Start Services Approval   | input `StartServicesApproval`, approver recorded in `START_APPROVER`                                                                                | Abort: nothing started, nothing restored                       |
| 7 Check Target Reachability | TCP checks from Jenkins, no job                                                                                                                     | Build fails before anything starts                             |
| 8 Start Services            | Same four jobs on the target, ACTION=Enable / start                                                                                                 | Undoes what this build started on the target                   |
| 9 WAF Traffic Switch        | `Thanos/FeeJunction/waf` · MIGRATION_DIRECTION (`DC_TO_DR`)                                                                                         | Nothing undone; check the website in the Indusface portal      |

## 3. Database pipeline: Thanos/FeeJunction/database_failover

One build fails over one database. Each stage is a separate run of `playbooks/failover_playbooks/db_failover_playbook.yml` with one tag. Stage 0 decides which of three paths the build takes. Shown for FEESJUNCTIONGENERIC (Availability Group `WL_FJ_AG`); the other two databases are identical with their own names.

```mermaid
flowchart TD
  A(["Start database_failover<br/>MIGRATION_DIRECTION=dc_to_dr · DATABASE=FEESJUNCTIONGENERIC<br/>SOURCE_DOWN_MODE=auto · one build at a time"]):::start
  PRE["Before every stage on the Ansible node<br/>00 topology: source db-dc-01, targets db-dr-01 + db-dr-02<br/>01 credentials /opt/AnsibleWin/IP_FEESJUNCTIONGENERIC.yml"]:::info

  S0["0 Check Source Database · tag check_source<br/>Ansible node: wait_for 172.16.51.3:5985, 3 tries, 20 s apart<br/>db-dc-01: SELECT state_desc FROM sys.databases<br/>writes /tmp/sql_backups/FEESJUNCTIONGENERIC_source_mode.txt<br/>and FEESJUNCTIONGENERIC_source_check.json"]:::stage
  Q{"What was found?"}:::decide
  XS(["STOP: server alive but database not readable,<br/>or OFFLINE / SUSPECT / MISSING<br/>nothing changed · DBA decides, force if needed"]):::bad

  subgraph NORMAL["Normal path: source ONLINE, no data loss"]
    N1["1 Log Shipping Check · log_shipping_check<br/>db-dc-01: msdb.dbo.log_shipping_monitor_primary<br/>writes /tmp/log_shipping_report.csv"]:::stage
    N2["2 Remove database from AG · remove_ag<br/>db-dc-01: ALTER AVAILABILITY GROUP WL_FJ_AG<br/>REMOVE DATABASE FEESJUNCTIONGENERIC<br/>then must be in no group and ONLINE"]:::stage
    N3["3 Disable Log Shipping · disable_log_shipping<br/>db-dc-01: LSBackup_FEESJUNCTIONGENERIC off<br/>db-dr-01 + db-dr-02: LSCopy / LSRestore off<br/>record /tmp/sql_backups/FEESJUNCTIONGENERIC_ls_jobs_before_HOST.json<br/>wait until no job runs, up to 10 min"]:::stage
    N3b["3b Check DB Sessions · check_db_sessions<br/>db-dc-01: wait 120 s, KILL remaining user sessions,<br/>wait 120 s more"]:::stage
    N4["4 Tail Backup · tail_backup · POINT OF NO RETURN<br/>db-dc-01: BACKUP LOG FEESJUNCTIONGENERIC TO<br/>\\172.16.51.3\X$\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\<br/>FEESJUNCTIONGENERIC_Final_YYYY-MM-DD_HH-MM-SS.trn<br/>WITH NORECOVERY: source goes RESTORING"]:::critical
    N5["5 Sync Backup between DBs · sync_backup<br/>chain from db-dc-01 msdb backupset, from each target's redo_start_lsn to _Final_<br/>fetch X:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\file to /tmp/sql_backups/FEESJUNCTIONGENERIC/<br/>win_copy to G:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\ on db-dr-01 and db-dr-02<br/>writes FEESJUNCTIONGENERIC_restore_plan_HOST.json"]:::stage
    N6["6 Database Recovery · database_recovery<br/>RESTORE HEADERONLY check against msdb<br/>RESTORE LOG ... WITH NORECOVERY in order on both targets<br/>both must reach the _Final_ last LSN<br/>writes FEESJUNCTIONGENERIC_restore_result_HOST.json"]:::stage
  end

  subgraph DOWN["Source-down path: db-dc-01 not answering, DATA LOSS"]
    D3["3 Disable Log Shipping, DR servers only<br/>db-dr-01 + db-dr-02: LSCopy / LSRestore off<br/>db-dc-01 not contacted"]:::stage
    D5["5S Sync Backup between DR servers · source_down_sync<br/>RESTORE HEADERONLY of recent .trn files on both DR servers<br/>finish line = furthest unbroken chain from db-dr-01's position<br/>missing files copied DR server to Ansible node to DR server<br/>writes FEESJUNCTIONGENERIC_restore_plan_HOST.json"]:::down
    D6["6S Restore Logs on DR servers · source_down_restore<br/>RESTORE LOG ... WITH NORECOVERY up to the finish line<br/>db-dr-01 must reach it, db-dr-02 warning only<br/>writes FEESJUNCTIONGENERIC_source_down_finish.json"]:::down
  end

  N7["7 Make Database online · online_seconday_database<br/>db-dr-01 only, if exactly at the _Final_ last LSN or the finish line:<br/>RESTORE DATABASE FEESJUNCTIONGENERIC WITH RECOVERY<br/>check ONLINE, MULTI_USER, READ_WRITE · users without a login<br/>db-dr-02 stays RESTORING<br/>writes FEESJUNCTIONGENERIC_online_result.json"]:::stage

  OK(["SUCCESS: database online on db-dr-01"]):::okend
  UNS(["UNSTABLE: online on db-dr-01 from DR copies<br/>description: SOURCE DOWN, data up to TIME"]):::warnend

  REEN(["post unsuccessful, failed before Tail Backup:<br/>10 reenable_log_shipping<br/>LSBackup on db-dc-01, recorded jobs on db-dr-01 / db-dr-02<br/>plus manual steps to re-add to WL_FJ_AG"]):::bad
  NX(["post always: publish records<br/>archiveArtifacts + curl -k to Nexus<br/>dc-dr-migration/feejunction/DATE/build-N_FEESJUNCTIONGENERIC_dc_to_dr/"]):::nexus

  A --> PRE --> S0 --> Q
  Q -->|"ONLINE: normal"| N1
  Q -->|"RESTORING: after_tail"| N5
  Q -->|"port 5985 closed: source_down"| D3
  Q -->|"anything else"| XS
  N1 --> N2 --> N3 --> N3b --> N4 --> N5 --> N6 --> N7
  D3 --> D5 --> D6 --> N7
  N7 -->|"normal / after_tail"| OK
  N7 -->|"source_down"| UNS
  N3 -.->|"failure before stage 4 succeeds"| REEN
  N3b -.-> REEN
  N4 -.->|"backup did not happen"| REEN
  OK --> NX
  UNS --> NX
  REEN --> NX
  XS --> NX

  classDef start fill:#1d5fbf26,stroke:#1d5fbf,stroke-width:2px
  classDef info fill:#56627314,stroke:#566273,stroke-dasharray:4 3
  classDef stage fill:#1d5fbf12,stroke:#1d5fbf
  classDef critical fill:#b3261e10,stroke:#b3261e,stroke-width:2px
  classDef down fill:#a35a0014,stroke:#a35a00
  classDef decide fill:#a35a0018,stroke:#a35a00,stroke-width:2px
  classDef bad fill:#b3261e14,stroke:#b3261e
  classDef okend fill:#1f7a4620,stroke:#1f7a46,stroke-width:2px
  classDef warnend fill:#a35a0020,stroke:#a35a00,stroke-width:2px
  classDef nexus fill:#1f7a4614,stroke:#1f7a46
```

| Stage 0 found                           | auto (snap)                                | never      | force       | Stages that run                              |
|-----------------------------------------|--------------------------------------------|------------|-------------|----------------------------------------------|
| Database ONLINE                         | normal        | normal     | source_down | 1, 2, 3, 3b, 4, 5, 6, 7                      |
| Database RESTORING (tail already taken) | after_tail    | after_tail | source_down | 5, 6, 7                                      |
| Port 5985 closed after 3 tries          | source_down | stop       | source_down | 3 (DR only), 5S, 6S, 7 · build ends UNSTABLE |
| Port open, login or SQL Server fails    | stop         | stop       | source_down | none                                         |
| OFFLINE, SUSPECT, MISSING, other        | stop         | stop       | source_down | none                                         |

## 4. How log backup files move

A Windows Remote Management session on a DR server cannot open the DC share with NTLM (the double-hop limit), so every copy goes through the Ansible node: fetched once, copied to each server that needs it, and the staging folder is always deleted afterwards.

```mermaid
flowchart LR
  subgraph SRC["db-dc-01 · 172.16.51.3"]
    F1["X:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\<br/>FEESJUNCTIONGENERIC_YYYYMMDDHHMMSS.trn<br/>FEESJUNCTIONGENERIC_Final_....trn"]
  end
  subgraph AN["Ansible node"]
    ST["/tmp/sql_backups/FEESJUNCTIONGENERIC/<br/>staging, each file once"]
  end
  subgraph TG["DR servers"]
    R1["db-dr-01 · G:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\"]
    R2["db-dr-02 · G:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\"]
  end
  F1 -->|"fetch, checksum"| ST
  ST -->|"win_copy force, only missing files"| R1
  ST -->|"win_copy force, only missing files"| R2
```

Normal path, stage 5. The list comes from db-dc-01 msdb (`backupset` + `backupmediafamily`).

```mermaid
flowchart LR
  subgraph TG["DR servers, source down"]
    R1["db-dr-01<br/>G:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\<br/>has 093000, 100000"]
    R2["db-dr-02<br/>G:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\<br/>has 093000, 094500"]
  end
  subgraph AN["Ansible node"]
    ST["/tmp/sql_backups/FEESJUNCTIONGENERIC/"]
  end
  R2 -->|"fetch 094500"| ST
  R1 -->|"fetch 100000"| ST
  ST -->|"win_copy 094500"| R1
  ST -->|"win_copy 100000"| R2
```

Source-down path, stage 5S. The list comes from `RESTORE HEADERONLY` on each DR server; db-dc-01 is never contacted.

## 5. Files and their locations

Every file the two pipelines read or write, for FEESJUNCTIONGENERIC. All records on the Ansible node are archived with the database build and uploaded to Nexus.

| File                                                                    | Where                                                                                                               | Written by                                   | Used by                                                                       |
|-------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|----------------------------------------------|-------------------------------------------------------------------------------|
| `FEESJUNCTIONGENERIC_YYYYMMDDHHMMSS.trn`                                | db-dc-01 `X:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\`; copies on db-dr-01/02 `G:\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\` | LSBackup job; LSCopy job; stages 5 / 5S      | LSRestore; stages 6 / 6S                                                      |
| `FEESJUNCTIONGENERIC_Final_YYYY-MM-DD_HH-MM-SS.trn`                     | db-dc-01 `\\172.16.51.3\X$\DB_BACKUPS\Tran\FEESJUNCTIONGENERIC\`                                                    | Stage 4 tail backup                          | Stages 5, 6, 7 (the finish line)                                              |
| `IP_DATABASE.yml` (3 per database)                                      | Ansible node `/opt/AnsibleWin/`                                                                                     | Set up by hand                               | Every stage (SQL Server name, Windows user, password)                         |
| `feejunction.ini`                                                       | `Thanos_FeeJunctionDB/inventories/`                                                                                 | Repository                                   | Every playbook (server order decides source and target)                       |
| `log_shipping_report.csv`                                               | Ansible node `/tmp/`                                                                                                | Stage 1                                      | Records, Nexus                                                                |
| `FEESJUNCTIONGENERIC_source_mode.txt`                                   | Ansible node `/tmp/sql_backups/`                                                                                    | Stage 0                                      | Jenkins: which stages run (also after Restart from Stage)                     |
| `FEESJUNCTIONGENERIC_source_check.json`                                 | Ansible node `/tmp/sql_backups/`                                                                                    | Stage 0                                      | Records, Nexus                                                                |
| `FEESJUNCTIONGENERIC_ls_jobs_before_db-dr-01.json`, `..._db-dr-02.json` | Ansible node `/tmp/sql_backups/`                                                                                    | Stage 3                                      | Undo (step 10): re-enable only these jobs. Deleted after stage 4 or the undo. |
| `FEESJUNCTIONGENERIC/` staging folder                                   | Ansible node `/tmp/sql_backups/`                                                                                    | Stages 5 / 5S                                | Deleted at the end of the copy, always                                        |
| `FEESJUNCTIONGENERIC_restore_plan_HOST.json`                            | Ansible node `/tmp/sql_backups/`                                                                                    | Stages 5 / 5S                                | Records, Nexus                                                                |
| `FEESJUNCTIONGENERIC_restore_result_HOST.json`                          | Ansible node `/tmp/sql_backups/`                                                                                    | Stages 6 / 6S                                | Records, Nexus                                                                |
| `FEESJUNCTIONGENERIC_source_down_finish.json`                           | Ansible node `/tmp/sql_backups/`                                                                                    | Stage 6S                                     | Stage 7 finish line; Jenkins build description                                |
| `FEESJUNCTIONGENERIC_online_result.json`                                | Ansible node `/tmp/sql_backups/`                                                                                    | Stage 7                                      | Records, Nexus                                                                |
| `jenkins_console.log`                                                   | Jenkins build                                                                                                       | Record step (needs `getLog` script approval) | Nexus                                                                         |

## 6. Mails from snap

Sent with the Email Extension plugin (`emailext`, HTML). Every mail carries the same header table: direction, JIRA, the selected databases, who started it, the snap build link, and the build notes. A mail that cannot be sent is a warning only.

| When                              | Subject                                                 | Body                                                                                                                                           |
|-----------------------------------|---------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| After 1 Prerequisite              | `[DC/DR DC->DR] Prerequisite: STATUS - snap #N`         | Prerequisite job link and result                                                                                                               |
| After 3 Stop Services             | `... Stop Services: STATUS ...`                         | Result, action, job, detail for the four stop jobs                                                                                             |
| At 4 DB Failover Approval         | `... DB Failover Approval: waiting for approval ...`    | Open the approval button, Stop Services table                                                                                                  |
| After 5 DB Failover               | `... DB Failover: STATUS ...`                           | Approver, one row per database; DATA LOSS note when UNSTABLE; ACTION NEEDED on failure                                                         |
| At 6 Start Services Approval      | `... Start Services Approval: waiting for approval ...` | Open the approval button, database results                                                                                                     |
| After 8 Start Services            | `... Start Services: STATUS ...`                        | Result table for the four start jobs                                                                                                           |
| After 9 WAF Traffic Switch        | `... WAF Traffic Switch: STATUS ...`                    | WAF job row; "customer traffic now goes to DR"                                                                                                 |
| End of every build (post cleanup) | `[DC/DR DC->DR] Final summary: RESULT - snap #N`        | Stage table with time into build, both approvers, Stop / Database / Start / WAF tables, automatic restore and undo tables, ACTION NEEDED notes |

### Recipients (DCDR_EMAIL_RECIPIENTS, same list as the deploy pipeline)

pgmonitoring@worldline.com · dl-applicationteam.ind@worldline.com · aniruddha.patil.external@worldline.com · vaishnavi.mahalle@worldline.com · shubham.pancham@worldline.com · sachin.gorad.external@worldline.com · mahadeer.h.external@worldline.com · vikas.yadav@worldline.com · kumara.dussa@worldline.com · sunil.sahu@worldline.com · nishesh.shukla@worldline.com

## 7. Nexus records

After every database build, whatever its result, Jenkins copies the record files written during that build from the Ansible node, archives them as Build Artifacts, and uploads each one. An upload failure is a warning; the artifacts stay on the build.

```mermaid
flowchart LR
  A["Ansible node<br/>/tmp/log_shipping_report.csv<br/>/tmp/sql_backups/DATABASE_*.json<br/>files newer than the build start only"] --> B["Jenkins workspace<br/>failover_records_N/<br/>+ jenkins_console.log"]
  B -->|"archiveArtifacts"| C["Build Artifacts<br/>download from the build page"]
  B -->|"curl -k --upload-file<br/>credential NEXUS_CREDS_ANI"| D[("https://172.16.15.34:8081/repository/<br/>dc-dr-migration/feejunction/YYYY-MM-DD/<br/>build-N_FEESJUNCTIONGENERIC_dc_to_dr/")]
```

## 8. DR to DC: what changes

The flow is the same; source and target swap.

| Item                                      | DC to DR                                                                      | DR to DC                                    |
|-------------------------------------------|-------------------------------------------------------------------------------|---------------------------------------------|
| Source database server                    | db-dc-01 172.16.51.3, `X:\DB_BACKUPS\Tran`                                    | db-dr-01 192.168.27.5, `G:\DB_BACKUPS\Tran` |
| Targets (online / restoring)              | db-dr-01 / db-dr-02, `G:\`                                                    | db-dc-01 / db-dc-02, `X:\`                  |
| Snap DIRECTION / database job / WAF job   | `DC->DR` / `dc_to_dr` / `DC_TO_DR`                                            | `DR->DC` / `dr_to_dc` / `DR_TO_DC`          |
| Prerequisite ENVIRONMENT, port check site | `prod_dr`, DR app servers                                                     | `prod_dc`, DC app servers                   |
| Stopped / started site                    | Stop DC (172.16.7.20, application_dc), start DR (192.168.2.5, application_dr) | Stop DR, start DC                           |

## 9. Rollback rules

| Where it stops                        | Source services                                            | Databases                                                                                                      | Target services                                   |
|---------------------------------------|------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|---------------------------------------------------|
| Prerequisite fails                    | Untouched                                                  | Untouched                                                                                                      | Untouched                                         |
| Stop Services fails or is aborted     | restored automatically        | Untouched                                                                                                      | Untouched                                         |
| DB Failover Approval aborted          | restored automatically        | Untouched                                                                                                      | Untouched                                         |
| Database job fails before Tail Backup | not restored: decide by hand | Log shipping re-enabled automatically; source still ONLINE; re-add to the Availability Group by hand           | Untouched                                         |
| Database job fails after Tail Backup  | not restored                 | No copy online anywhere: finish with Restart from Stage, or `RESTORE DATABASE ... WITH RECOVERY` on the source | Untouched                                         |
| Source-down database stage fails      | Source is down                                             | No copy online; Restart from Stage 5S, 6S or 7                                                                 | Untouched                                         |
| Start Services Approval aborted       | not restored                 | Online on the target                                                                                           | Not started                                       |
| Start Services fails or is aborted    | Stopped                                                    | Online on the target                                                                                           | undone automatically |
| WAF switch fails                      | Stopped                                                    | Online on the target                                                                                           | Running; nothing undone, check the WAF by hand    |

After a source-down failover the old source must not take traffic again if it comes back: it may hold transactions the new primary does not have.

