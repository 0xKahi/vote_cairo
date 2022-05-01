%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin

@storage_var
func poll_result(poll_id : felt) -> (result : felt):
end

# poll finalazed state
@storage_var
func poll_final_state(poll_id : felt) -> (res : felt):
end

@external
func record{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    poll_id : felt, result : felt
):
    # finalize poll state
    poll_final_state.write(poll_id=poll_id, value=1)
    # commit poll results
    poll_result.write(poll_id=poll_id, value=result)
    return ()
end

@external
func verify_finalized{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    poll_id : felt
):
    let (not_finalized) = poll_final_state.read(poll_id=poll_id)
    assert not_finalized = 0
    return ()
end

@view
func get_poll_results{syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*}(
    poll_id : felt
) -> (result : felt):
    let (result) = poll_result.read(poll_id=poll_id)
    return (result=result)
end
