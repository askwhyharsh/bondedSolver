mod pb;

use pb::example::{Events, Vault, Position};
use substreams::Hex;
use substreams_entity_change::pb::entity::EntityChanges;
use substreams_entity_change::tables::Tables;
use substreams_ethereum::pb::eth;
use hex;

const FACTORY_ADDRESS: &str = "0x008D4Dd934f9811E768F71AbCe59E193DC407CF8";
const VAULT_CREATED_SIG: &str = "0xb9f84b8e65164b14439ae3620519ba4d2af4c96b1396b1772946e897159a45a7";
const POSITION_OPENED_SIG: &str = "0x3c92d699a2f0cd9742c8a14eba5a8ad4b514a480ee8a297e3304a1e97c2b332d";

#[substreams::handlers::map]
fn map_events(block: eth::v2::Block) -> Result<Events, substreams::errors::Error> {
    let mut vaults = Vec::new();
    let mut positions = Vec::new();

    for log in block.logs() {
        if is_vault_created_event(&log.log) {
            let vault = Vault {
                address: format!("0x{}", Hex(&log.log.address)),
                token0: format!("0x{}", Hex(&log.log.topics[1])),
                token1: format!("0x{}", Hex(&log.log.topics[2])),
                vault_id: decode_uint256(&log.log.data) as u64,
                block_number: block.number,
                timestamp: block.timestamp_seconds().to_string(),
                factory: FACTORY_ADDRESS.to_string(),
            };
            vaults.push(vault);
        }

        if is_position_opened_event(&log.log) {
            let position = Position {
                position_id: decode_uint256(&log.log.data) as u64,
                owner: format!("0x{}", Hex(&log.log.topics[1])),
                amount0: format!("0x{}", Hex(&log.log.topics[2])),
                amount1: format!("0x{}", Hex(&log.log.topics[3])),
                block_number: block.number,
                timestamp: block.timestamp_seconds().to_string(),
                vault: format!("0x{}", Hex(&log.log.address)),
            };
            positions.push(position);
        }
    }

    Ok(Events { vaults, positions })
}

#[substreams::handlers::map]
pub fn graph_out(events: Events) -> Result<EntityChanges, substreams::errors::Error> {
    let mut tables = Tables::new();

    for vault in events.vaults {
        tables
            .create_row("Vault", vault.address.clone())
            .set("address", vault.address)
            .set("token0", vault.token0)
            .set("token1", vault.token1)
            .set("vaultId", vault.vault_id)
            .set("timestamp", vault.timestamp)
            .set("blockNumber", vault.block_number)
            .set("factory", vault.factory);
    }

    for position in events.positions {
        tables
            .create_row("Position", position.position_id.to_string())
            .set("positionId", position.position_id)
            .set("owner", position.owner)
            .set("amount0", position.amount0)
            .set("amount1", position.amount1)
            .set("timestamp", position.timestamp)
            .set("blockNumber", position.block_number)
            .set("vault", position.vault);
    }

    Ok(tables.to_entity_changes())
}

fn is_vault_created_event(log: &eth::v2::Log) -> bool {
    let topic0 = &log.topics[0];
    let sig = hex::decode(VAULT_CREATED_SIG.trim_start_matches("0x")).unwrap();
    topic0 == sig.as_slice()
}

fn is_position_opened_event(log: &eth::v2::Log) -> bool {
    let topic0 = &log.topics[0];
    let sig = hex::decode(POSITION_OPENED_SIG.trim_start_matches("0x")).unwrap();
    topic0 == sig.as_slice()
}

fn decode_uint256(data: &[u8]) -> u64 {
    let mut bytes = [0u8; 8];
    bytes.copy_from_slice(&data[24..32]);
    u64::from_be_bytes(bytes)
}