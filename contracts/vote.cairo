%lang starknet

%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_not_zero, assert_not_equal
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.starknet.common.syscalls import get_caller_address

@constructor
func constructor{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    recorder_address : felt
):
    recorder_contract.write(value=recorder_address)
    return ()
end

# ? ========================= storage variables =======================================#
# recoder contract address
@storage_var
func recorder_contract() -> (recorder_address : felt):
end
# poll owners public key and address
@storage_var
func poll_owner_key_addr(poll_id : felt) -> (key_addr : (felt, felt)):
end
# stores the number of votes to a specific answer mapping answer to a poll id and the count to that answer
@storage_var
func poll_vote_state(poll_id : felt, answer : felt) -> (count : felt):
end
# nested mapping storage variable to check if voters are registered to a poll
# by mapping poll ids to a voter public key and mapping that key to a felt
@storage_var
func registered_voters(poll_id : felt, voter_public_key : felt) -> (is_registered : felt):
end
# nested mapping storage var that checks if a user has voted for a specific poll
@storage_var
func voting_state(poll_id : felt, voter_public_key : felt) -> (result : felt):
end
# nested mapping that checks the users answer to a certain poll
@storage_var
func voter_answer(poll_id : felt, voter_public_key : felt) -> (answer : felt):
end

# ? =============================== functions =======================================#
# initalize poll to owners public key
@external
func init_poll{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    poll_id : felt, public_key : felt
):
    with_attr error_message("Poll_id: {poll_id} already exist"):
        let (poll_data_tuple) = poll_owner_key_addr.read(poll_id=poll_id)
        assert poll_data_tuple[0] = 0
    end
    let (caller_address) = get_caller_address()
    poll_owner_key_addr.write(poll_id=poll_id, value=(public_key, caller_address))
    return ()
end

# let users register to polls
@external
func register_voter{
    syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*, ecdsa_ptr : SignatureBuiltin*
}(poll_id : felt, voter_public_key : felt, r : felt, s : felt):
    # verify that poll has been initalized
    with_attr error_message("poll_id: {poll_id} has not been initalized"):
        let (poll_data_tuple) = poll_owner_key_addr.read(poll_id=poll_id)
        assert_not_zero(poll_data_tuple[0])
    end
    # getting the message that the owner supossedly should sign which is the hash of pollid and voter public key
    let (message) = hash2{hash_ptr=pedersen_ptr}(x=poll_id, y=voter_public_key)
    # check if  actually signed the message (poll_id + owner public key)
    verify_ecdsa_signature(
        message=message, public_key=poll_data_tuple[0], signature_r=r, signature_s=s
    )

    registered_voters.write(poll_id=poll_id, voter_public_key=voter_public_key, value=1)
    return ()
end

# get the count of each answer of certain poll
@view
func get_voting_state{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    poll_id : felt
) -> (no_votes_len : felt, yes_votes_len : felt):
    let (no_count) = poll_vote_state.read(poll_id=poll_id, answer=0)
    let (yes_count) = poll_vote_state.read(poll_id=poll_id, answer=1)
    return (no_votes_len=no_count, yes_votes_len=yes_count)
end

# ? =============================== helper functions =======================================#
# helper function to check users voting states
func verify_vote{
    syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*, ecdsa_ptr : SignatureBuiltin*
}(poll_id : felt, voter_public_key : felt, vote : felt, r : felt, s : felt):
    # verify that vote value is either 1(yes) or 0(no)
    assert (vote - 0) * (vote - 1) = 0
    # verify if voters are registered
    let (is_registered) = registered_voters.read(poll_id=poll_id, voter_public_key=voter_public_key)
    assert_not_zero(is_registered)
    # verify that voter has not voted
    let (has_voted) = voting_state.read(poll_id=poll_id, voter_public_key=voter_public_key)
    assert has_voted = 0
    # verify voter signature which supposedly signs hash (poll_id,vote)
    let (message) = hash2{hash_ptr=pedersen_ptr}(x=poll_id, y=vote)
    verify_ecdsa_signature(
        message=message, public_key=voter_public_key, signature_r=r, signature_s=s
    )
    return ()
end

# helper function to check users voting states
func verify_change_vote{
    syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*, ecdsa_ptr : SignatureBuiltin*
}(poll_id : felt, voter_public_key : felt, vote : felt, r : felt, s : felt):
    # verify that vote value is either 1(yes) or 0(no)
    assert (vote - 0) * (vote - 1) = 0
    # verify if voters are registered
    let (is_registered) = registered_voters.read(poll_id=poll_id, voter_public_key=voter_public_key)
    assert_not_zero(is_registered)
    # verify that voter has voted and that vote is not the same
    let (has_voted) = voting_state.read(poll_id=poll_id, voter_public_key=voter_public_key)
    assert_not_zero(has_voted)
    # get voters answer
    let (prev_vote) = voter_answer.read(poll_id=poll_id, voter_public_key=voter_public_key)
    assert_not_equal(vote, prev_vote)
    # verify voter signature which supposedly signs hash (poll_id,vote)
    let (message) = hash2{hash_ptr=pedersen_ptr}(x=poll_id, y=vote)
    verify_ecdsa_signature(
        message=message, public_key=voter_public_key, signature_r=r, signature_s=s
    )
    return ()
end

# helper function to check if caller is owner
func verify_owner{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    poll_id : felt
):
    let (poll_data_tuple) = poll_owner_key_addr.read(poll_id=poll_id)
    let (caller_address) = get_caller_address()
    assert poll_data_tuple[1] = caller_address
    return ()
end

# helper function to see if poll is finalized
func verify_poll_final{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    poll_id : felt
):
    alloc_locals
    let (local recorder_addr) = recorder_contract.read()
    IRecorderContract.verify_finalized(contract_address=recorder_addr, poll_id=poll_id)
    return ()
end
# ? =================================== end ============================================#
# let users vote
@external
func vote{
    syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*, ecdsa_ptr : SignatureBuiltin*
}(voter_public_key : felt, vote : felt, poll_id : felt, r : felt, s : felt):
    verify_poll_final(poll_id=poll_id)
    verify_vote(poll_id=poll_id, voter_public_key=voter_public_key, vote=vote, r=r, s=s)
    # vote
    let (vote_count) = poll_vote_state.read(poll_id=poll_id, answer=vote)
    # set voter state to has voted
    voting_state.write(poll_id=poll_id, voter_public_key=voter_public_key, value=1)
    # set voter answer
    voter_answer.write(poll_id=poll_id, voter_public_key=voter_public_key, value=vote)
    # add count to answwer
    poll_vote_state.write(poll_id=poll_id, answer=vote, value=vote_count + 1)
    return ()
end

# let users change their vote
@external
func vote_change{
    syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*, ecdsa_ptr : SignatureBuiltin*
}(voter_public_key : felt, vote : felt, poll_id : felt, r : felt, s : felt):
    verify_poll_final(poll_id=poll_id)
    verify_change_vote(poll_id=poll_id, voter_public_key=voter_public_key, vote=vote, r=r, s=s)
    let (prev_vote) = voter_answer.read(poll_id=poll_id, voter_public_key=voter_public_key)
    # vote count of current answer
    let (vote_count_1) = poll_vote_state.read(poll_id=poll_id, answer=vote)
    # vote count of previous answer
    let (vote_count_2) = poll_vote_state.read(poll_id=poll_id, answer=prev_vote)
    poll_vote_state.write(poll_id=poll_id, answer=vote, value=vote_count_1 + 1)
    poll_vote_state.write(poll_id=poll_id, answer=prev_vote, value=vote_count_2 - 1)
    return ()
end

@external
func finalize_poll{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    poll_id : felt
):
    alloc_locals
    with_attr error_message("poll:{poll_id} not owned by account"):
        verify_owner(poll_id=poll_id)
    end
    verify_poll_final(poll_id=poll_id)

    let (local recorder_addr) = recorder_contract.read()
    let (no_votes_len, yes_votes_len) = get_voting_state(poll_id=poll_id)
    # storing pointers to local variables as they might get revoked by is_le_felt
    local syscall_ptr : felt* = syscall_ptr
    local pedersen_ptr : HashBuiltin* = pedersen_ptr
    let (result) = is_le_felt(no_votes_len, yes_votes_len)
    # using short strings to avoid mixup between zero result of storage variables and the zero default value of storage variables
    let result = (result * 'Yes') + ((1 - result) * 'No')
    # record the poll result
    IRecorderContract.record(contract_address=recorder_addr, poll_id=poll_id, result=result)
    return ()
end

# ? ========================= interface ===================================#
@contract_interface
namespace IRecorderContract:
    func record(poll_id : felt, result : felt):
    end

    func verify_finalized(poll_id : felt):
    end
end
