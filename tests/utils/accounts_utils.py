import os
from utils.utils import Signer
ACCOUNT_FILE = os.path.join("contracts", "Account.cairo")

class Account():
    def __init__(self,private_key):
        self.signer = Signer(private_key)
        self.contract = None
        self.address = 0
        self.public_key = 0

    async def create(self,starknet):
        contract = await starknet.deploy(ACCOUNT_FILE,constructor_calldata=[self.signer.public_key])
        self.public_key = self.signer.public_key 
        self.contract = contract
        self.address = contract.contract_address

    async def tx_with_nonce(self,to,selector_name,calldata):
        nonce_info = await self.contract.get_nonce().call()
        nonce, = nonce_info.result
        await self.signer.send_transactions(
            self.contract, 
            [(to,selector_name,calldata)],
            nonce
        )