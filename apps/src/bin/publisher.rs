// Copyright 2024 RISC Zero, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// This application demonstrates how to send an off-chain proof request
// to the Bonsai proving service and publish the received proofs directly
// to your deployed app contract.

use alloy_primitives::{Address, U256};
use alloy_sol_types::{sol, SolCall};
use anyhow::Result;
use apps::TxSender;
// use bonsai_sdk::alpha as bonsai_sdk;
use clap::Parser;
use methods::BALANCE_OF_ELF;
use risc0_ethereum_contracts::groth16::encode;
// use risc0_groth16::Seal;
use risc0_steel::{config::ETH_SEPOLIA_CHAIN_SPEC, ethereum::EthEvmEnv, Contract, EvmBlockHeader};
use risc0_zkvm::{default_prover, ExecutorEnv, ProverOpts, VerifierContext};
// use std::fs::File;
// use std::io::BufReader;
use tracing_subscriber::EnvFilter;

sol!("../contracts/ICounter.sol");

/// Arguments of the publisher CLI.
#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    /// Ethereum chain ID
    #[clap(long)]
    chain_id: u64,

    /// Ethereum Node endpoint.
    #[clap(long, env)]
    eth_wallet_private_key: String,

    /// Ethereum Node endpoint.
    #[clap(long, env)]
    rpc_url: String,

    /// Counter's contract address on Ethereum
    #[clap(long)]
    contract: Address,

    /// Account address to read the balance_of on Ethereum
    #[clap(long)]
    account: Address,

    // Amount that the account should have
    #[clap(long)]
    amount: U256,
}

fn main() -> Result<()> {
    // Initialize tracing. In order to view logs, run `RUST_LOG=info cargo run`
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    // parse the command line arguments
    let args = Args::parse();

    // Create an EVM environment from an RPC endpoint and a block number. If no block number is
    // provided, the latest block is used.
    let mut env = EthEvmEnv::from_rpc(&args.rpc_url, None)?;
    //  The `with_chain_spec` method is used to specify the chain configuration.
    env = env.with_chain_spec(&ETH_SEPOLIA_CHAIN_SPEC);

    // // Prepare the function call
    // let call = IERC20::balanceOfCall {
    //     account: args.account,
    // };

    let call = ICounter::balanceOfCall {
        account: args.account,
    };
    // Preflight the call to execute the function in the guest.
    let mut contract = Contract::preflight(args.contract, &mut env);
    let returns = contract.call_builder(&call).call()?;
    println!(
        "For block {} calling `{}` on {} returns: {}",
        env.header().number(),
        ICounter::balanceOfCall::SIGNATURE,
        args.contract,
        returns._0
    );

    println!("proving...");
    let view_call_input = env.into_input()?;
    let env = ExecutorEnv::builder()
        .write(&view_call_input)?
        .write(&args.contract)?
        .write(&args.account)?
        .write(&args.amount)?
        .build()?;

    let receipt = default_prover()
        .prove_with_ctx(
            env,
            &VerifierContext::default(),
            BALANCE_OF_ELF,
            &ProverOpts::groth16(),
        )?
        .receipt;
    println!("proving...done");

    // Create a new `TxSender`.
    let tx_sender = TxSender::new(
        args.chain_id,
        &args.rpc_url,
        &args.eth_wallet_private_key,
        &args.contract.to_string(),
    )?;
    // Encode the groth16 seal with the selector
    let seal = encode(receipt.inner.groth16()?.seal.clone())?;
    let journal = receipt.journal.bytes.clone();
    // Encode the function call for `ICounter.verify(journal, seal)`.
    let calldata = ICounter::verifyCall {
        journalData: journal.into(),
        seal: seal.into(),
    }
    .abi_encode();

    // Proof with the snark receipt
    // --------------------------------
    // let snark_receipt_raw = include_str!("../../snark.json");
    // let snark_receipt: bonsai_sdk::responses::SnarkReceipt =
    //     serde_json::from_str(snark_receipt_raw)?;
    // let calldata = ICounter::incrementCall {
    //     journalData: snark_receipt.journal.into(),
    //     seal: encode(snark_receipt.snark.to_vec().into())?.into(),
    // }
    // .abi_encode();
    // println!("{:?}", calldata);
    // --------------------------------

    // Encode the function call for `ICounter.increment(journal, seal)`.
    // Send the calldata to Ethereum.
    println!("sending tx...");
    let runtime = tokio::runtime::Runtime::new()?;
    runtime.block_on(tx_sender.send(calldata))?;
    println!("sending tx...done");

    Ok(())
}
