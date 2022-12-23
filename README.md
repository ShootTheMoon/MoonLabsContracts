# Moon Labs Utility Contracts

MoonLockVesting.sol - Proxy Contract
- Users can create vesting instances for other wallets.
- Users can choose from either a linear lock or a standard(Bulk).
- Lock type is determined bt startDate, if startDate is 0 then lock is standard(Bulk). This will be abstracted by the front end ui.
- Lock creators cannot modify locks once already created.
- Withdraw owners can transfer locks to other addresses.
- A set percentage of eth derived from vesting creations is used to buyback and burn the MLAB native token.
- Users can input a referral code and receive X percent discount while the referral code owner receives X percent of the sale.

MoonLockReferral.sol - Standard Contract
- User can create a referral code to use with Moon Labs contracts.
- User can transfer their address bound code to another address.
- User can delete their address bound code.
- One code per address and one address per code.
- Owner can pre reserve codes for later use.
- Reserved codes are not bound to any address.
- Reserved codes can be assigned by the contract owner.
- All codes are stored in uppercase. Numbers and characters are permitted and there is no size limit as of now.


To be added:
- A way to accommodate rebase tokens or tokens where total supply fluctuates 
- More efficient way to distribute commission rewards