""" voting contract test"""
import os
import pytest
import pytest_asyncio
from starkware.starknet.testing.starknet import Starknet
from starkware.crypto.signature.signature import pedersen_hash
from utils.utils import contract_path
from utils.accounts_utils import Account

# The path to the contract source code.
ACCOUNT_FILE = os.path.join("contracts", "Account.cairo")
VOTE_FILE = os.path.join("contracts", "vote.cairo")
RECORDER_FILE = os.path.join("contracts", "recorder.cairo")
INITALIZABLE_FILE = os.path.join("contracts","initalizable.cairo")

FAKE_PKEY = 123456789987654321
NUM_OF_ACC = 2

@pytest_asyncio.fixture(scope="module")
async def account_factory():
    starknet = await Starknet.empty()
    accounts = []
    for i in range(NUM_OF_ACC):
        account = Account(FAKE_PKEY+i)
        await account.create(starknet)
        accounts.append(account)
        print(f"Account {i} initalized: {account}")
    return starknet, accounts

@pytest_asyncio.fixture(scope="module")
async def contract_factory(account_factory):
    starknet, accounts = account_factory
    recorder_contract = await starknet.deploy(RECORDER_FILE)
    vote_contract = await starknet.deploy(source=VOTE_FILE,constructor_calldata=[recorder_contract.contract_address])
    return starknet, accounts, vote_contract, recorder_contract

@pytest.mark.asyncio
async def test_account_contract(contract_factory):
    _, accounts, _, _= contract_factory
    user_1 = accounts[0]
    pkey = await user_1.contract.get_public_key().call()
    assert pkey.result == (user_1.public_key,)

@pytest.mark.asyncio
async def test_execute(contract_factory):
    starknet, accounts,_,_ = contract_factory
    initializable = await starknet.deploy(INITALIZABLE_FILE)

    execution_info = await initializable.initialized().call()
    assert execution_info.result == (0,)

    await accounts[0].signer.send_transactions(accounts[0].contract, [(initializable.contract_address, 'initialize', [])])
    #await accounts[0].tx_with_nonce(initializable.contract_address,'initalize',[])
    execution_info = await initializable.initialized().call()
    assert execution_info.result == (1,)

@pytest.mark.asyncio
async def test_vote(contract_factory):
    _, accounts, vote_contract, _= contract_factory
    user_1 = accounts[0]
    user_2 = accounts[1]
    poll_id = 1
    #creating poll
    trsc = await user_1.tx_with_nonce(vote_contract.contract_address, "init_poll",[poll_id, user_1.public_key])
    print(trsc)
    # creating message for owner to sign to register voter
    register_msg_hash = await pedersen_hash(1,user_2.public_key) 
    (r,s) = await user_1.signer.sign(register_msg_hash)
    # register user_2 as a voter for poll id 1
    await vote_contract.register_voter(poll_id=1,voter_public_key=user_2.public_key,r=r,s=s).invoke()
    # creating message for voters to sign wwhen they vote 
    vote_msg_hash = await pedersen_hash(poll_id,1)
    (r,s) = await user_2.signer.sign(vote_msg_hash)
    await vote_contract.vote(voter_public_key=user_2.public_key,vote=1,poll_id=poll_id,r=r,s=s).invoke()
    assert await vote_contract.get_voting_state(poll_id=1).call == (0,1)
    




