# Setting up a Solana RPC node with Ansible

 1. [Introduction](#solana-ansible-rpc-role)
 2. [Hardware Requirements](#hardware-requirements)
 3. [Software Requirements](#software-requirements)
 4. [Role Variables](#role-variables)
 5. [Basic variables](#basic-variables)
 6. [Network Specific Variables](#network-specific-variables)
 7. [RPC Specific Variables](#rpc-specific-variables)
 8. [Performance Variables](#performance-variables)
 9. [Bigtable](#bigtable)
 10. [Handling Forks](#handling-forks)
 11. [CPU Governor & Sysctl Settings](#cpu-governor-and-sysctl-settings)
 12. [Example Playbooks](#example-playbooks)
 13. [Running the RPC Node](#running-the-rpc-node)

## Solana Ansible RPC Role

An Ansible role to deploy a Solana RPC node. This configures the validator software in RPC mode running under the user `solana`. The RPC service is installed as a user service running under this same user. 

## Hardware Requirements

A Solana RPC server requires _at least_ the same specs as a Solana validator node, but depending on the usage it should have higher requirements. We recommend using at least a 16 cores, 32 threads CPU with 2.8 GHz clock base, 256 GB of RAM in order to store indexes and 2 TB NVMe to store the Ledger. For more information about hardware requirements, please refer to [https://docs.solana.com/running-validator/validator-reqs](https://docs.solana.com/running-validator/validator-reqs).

## Software Requirements

 * Ansible >= 2.8
 * Ubuntu 18.04+ on the target deployment machine 

This role assumes some familiarity with the Solana validator software deployment process.

## Role Variables

The deploy ensures that the checksum for the version of solana-installer that you are downloading matches one given in `vars/main.yml`. In case you want to install a solana version not listed there, it is good if you first download and check the sha256 checksum of the solana-installer script (https://raw.githubusercontent.com/solana-labs/solana/install/solana-install-init.sh).

There are a large number of configurable parameters for Solana. Many of these have workable defaults, and you can use this role to deploy a Solana RPC node without changing any of the default values. If you run this role without specifying any parameters, it'll configure a standard `mainnet` RPC node. 

### Basic Variables

These are the basic variables that configure the setup of the validators. They have default values but you probably want to customise them based on your setup.

| Name                 | Default value        | Description                |
|----------------------|----------------------|----------------------------|
| `solana_version` | stable | The solana version to install. |
| `solana_root`        | /solana              | Main directory for solana ledger and accounts |
| `solana_ledger_location` | /home/solana/ledger | Storage for solana ledger (should be on NVME) |
| `solana_accounts_location` | /mnt/accounts | Tmpfs location for solana accounts information. |
| `solana_tmpfs_size` | 300G | Tmpfs size. |
| `solana_keypairs` | `[]` | List of keypairs to copy to the validator node. Each entry in the list should have a `key` and `name` entry. This will create `/home/solana/<name>.json` containing the value of `key`. |
| `solana_generate_keypair` | true | Whether or not to generate a keypair. If you haven't specified `solana_keypairs` and you set this to true, a new key will be generated and placed in /home/solana/identity.json |
| `solana_public_key` | `/home/solana/identity.json` | Location of the identity of the validator node. |
| `solana_network` | mainnet | The solana network that this node is supposed to be part of |
| `solana_environment` | see defaults/main.yml | Environment variables to specify for the validator node, most importantly `RUST_LOG` |
| `solana_enabled_services` | `[ solana-validator ]`  | List of services to start automatically on boot |
| `solana_disabled_services` | `[ ]` | List of services to set as disabled |
| `solana_gossip_port` | 8001 | Port for gossip traffic (needs to be open publicly in firewall) |
| `solana_rpc_port` | 8899 | Port for incoming RPC. This is typically only open on localhost. Place a proxy like `haproxy` in front of this port. |
| `solana_dynamic_port_range` | 8002-8012 | Port for incoming solana traffic. Needs to be open publicly in firewall. |
| `log_rotation` | true | Sets up daily log rotation for 7 days |
| `solana_logs_location` | /home/solana/log | Solana logs location. |

### Network Specific Variables

Default values for these variables are specified in `vars/{{ solana_network }}-default.yml` (e.g. `vars/mainnet-default.yml`). You can also specify your own by providing the file `{{ solana_network }}.yml`. You will need to specify all these variables unless you rely on the defaults.

| Name                 | Default value        | Description                |
|----------------------|----------------------|----------------------------|
| `solana_network` | mainnet | The solana network this node should join     |
| `solana_metrics_config` | see vars/mainnet-default.yml | The metrics endpoint |
| `solana_genesis_hash` | see vars/mainnet-default.yml | The genesis hash for this network |
| `solana_entrypoints` | see vars/mainnet-default.yml | Entrypoint hosts |
| `solana_trusted_validators` | see vars/mainnet-default.yml | Trusted validators from where to fetch snapshots and genesis bin on start up |
| `solana_expected_bank_hash` | see vars/mainnet-default.yml | Expected bank hash |
| `solana_expected_shred_version` | see vars/mainnet-default.yml | Expected shred version |
| `solana_index_exclude_keys` | see vars/mainnet-default.yml | Keys to exclude from indexes for performance reasons |

### RPC Specific Variables

| Name                 | Default value        | Description                |
|----------------------|----------------------|----------------------------|
| `solana_rpc_faucet_address` | | Specify an RPC faucet |
| `solana_rpc_history` | true | Whether to provide historical values over RPC |
| `solana_account_index` | program-id spl-token-owner spl-token-mint | Which indexes to enable. These greatly improve performance but slows down start up time and can increase memory requirements. |

### Performance Variables

These are variables you can tweak to improve performance

| Name                 | Default value        | Description                |
|----------------------|----------------------|----------------------------|
| `solana_snapshot_compression` |  | Whether to compress snapshots or not. Specify none to improve performance.  |
| `solana_snapshot_interval_slots` | | How often to take snapshots. Increase to improve performance. Suggested value is 500. |
| `solana_pubsub_max_connections` | 1000 | Maximum number of pubsub connections to allow. |
| `solana_bpf_jit` | | Whether to enable BPF JIT . Default on for devnet. |
| `solana_banking_threads` | 16 | Number of banking threads. |
| `solana_rpc_threads` | | Number of RPC threads (default maximum threads/cores on system) |
| `solana_limit_ledger_size` | `solana default, 250 mio` | Size of the local ledger to store. For a full epoch set a value between 350 mio and 500 mio. For best performance set 50 (minimal value). |
| `solana_accounts_db_caching` | | Whether to enable accounts db caching |
| `solana_accounts_shrink_path` | | You may want to specify another location for the accounts shrinking process |

## Bigtable

You can specify Google Bigtable account credentials for querying blocks not present in local ledger.

| Name                 | Default value        | Description                |
|----------------------|----------------------|----------------------------|
| `solana_bigtable_enabled` | false | Enable bigtable access |
| `solana_bigtable_project_id` | | Bigtable project id |
| `solana_bigtable_private_key_id` | | Bigtable private key id |
| `solana_bigtable_private_key` | | Bigtable private key |
| `solana_bigtable_client_email` | | Bigtable client email |
| `solana_bigtable_client_id` | | Bigtable client id |
| `solana_bigtable_client_x509_cert_url` | | Bigtable cert url  |


## Handling Forks

Occasionally devnet/testnet will experience forks. In these cases use the following parameters as instructed in Discord:

| Name                 | Default value        | Description                |
|----------------------|----------------------|----------------------------|
| `solana_hard_fork` |  | Hard fork |
| `solana_wait_for_supermajority` |  | Whether node should wait for supermajority or not |

## CPU Governor and Sysctl Settings

There are certain configurations that you need to do to get your RPC node running properly. This role can help you make some of these standard config changes. However, full optmisation depends greatly on your hardware so you need to take time to be familiar with how to configure your hardware right.

The most important element of optimisation is the CPU performance governor. This controls boost behaviour and energy usage. On many hosts in DCs they are configured for balance between performance and energy usage. To set the servers CPU governor there are three options:
	
 1. You have access to BIOS and you set the BIOS cpu setting to `max performance`. This works well for HPE systems. In this case, specify the variable `cpu_governor: bios`. This is sometimes required for AMD EPYC systems too.
 2. You have acccess to BIOS and you set the BIOS cpu setting to `os control`. This should be the typical default. In this case you can leave the `cpu_governor` variable as default or set it explicitly to `cpu_governor: performance`.
 3. You don't have access to BIOS or CPU governor settings. If possible, try to set `cpu_governor: performance`. Otherwise, hopefully your provider has configured it for good performance.

The second config you need to do is to edit various kernel parameters to fit the Solana RPC use case.

One option is to deploy `solana-sys-tuner` together with this config to autotune some variables for you. 

A second option, especially if you are new to tuning performance is `tuned` and `tune-adm` from RedHat, where the `throughput-performance` profile is suitable. 

Finally, if you deploy through this role you can also specify a list of sysctl values for this playbook to automatically set up on your host. This allows full control and sets them so that they are permanently configured.
Here is a list of sysctl values that might help:

```
sysctl_optimisations:
  vm.max_map_count: 700000
  kernel.nmi_watchdog: 0
# Minimal preemption granularity for CPU-bound tasks:
# (default: 1 msec#  (1 + ilog(ncpus)), units: nanoseconds)
  kernel.sched_min_granularity_ns: '10000000'
# SCHED_OTHER wake-up granularity.
# (default: 1 msec#  (1 + ilog(ncpus)), units: nanoseconds)
  kernel.sched_wakeup_granularity_ns:  '15000000' 
  vm.swappiness: '30'
  kernel.hung_task_timeout_secs: 600
# this means that virtual memory statistics is gathered less often but is a reasonable trade off for lower latency
  vm.stat_interval: 10
  vm.dirty_ratio: 40
  vm.dirty_background_ratio: 10
  vm.dirty_expire_centisecs: 36000
  vm.dirty_writeback_centisecs: 3000
  vm.dirtytime_expire_seconds: 43200
  kernel.timer_migration: 0
# A suggested value for pid_max is 1024 * <# of cpu cores/threads in system>
  kernel.pid_max: 65536
  net.ipv4.tcp_fastopen: 3
# From solana systuner
# Reference: https://medium.com/@CameronSparr/increase-os-udp-buffers-to-improve-performance-51d167bb1360
  net.core.rmem_max: 134217728
  net.core.rmem_default: 134217728
  net.core.wmem_max: 134217728
  net.core.wmem_default: 134217728
```

## Example Playbooks

Mainnet node:

```
    - hosts: solana_rpc_nodes
      become: true
      become_method: sudo
      roles:
         - { role: solana.solana-validator, solana_network: mainnet }
```

Testnet node:

```
    - hosts: solana_rpc_nodes
      become: true
      become_method: sudo
      roles:
         - { role: solana.solana-validator, solana_network: testnet }
```

Devnet node:

```
    - hosts: solana_rpc_nodes
      become: true
      become_method: sudo
      roles:
         - { role: solana.solana-validator, solana_network: devnet }
```

## Running the RPC Node

After the deploy you can login to the machine and run `su -l solana` to become the solana user. 

To see the Solana validator command line generated for you during the deploy you can take a look at `/home/solana/bin/solana-validator.sh`. Remember that any changes to this file will be overwritten next time you run the playbook.

For the first start up, you should comment out `--no-genesis-fetch` and `--no-snapshot-fetch` in the file `/home/solana/bin/solana-rpc.sh`. This will allow you node to download the basic files it requires for first time start up. Remember to activate these lines again after you have started the validator for the first time or it'll keep downloading the files on every restart.

Then start up the Solana RPC process by running `systemctl --user start solana-validator`. You can see status of the process by running `systemctl --user status solana-validator`. The first start up will take some time. You can monitor start up by running `solana catchup --our-localhost`.

## License

MIT

