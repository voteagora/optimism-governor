# Optimism Governor Tools

This directory contains various scripts for managing the Optimism Governor and its Timelock Controller.

## Proposal Cancellation Tools

Tools for the Foundation's L2 Safe (or Security Council) to cancel queued proposals in the timelock if they are malicious can be found in the `cancel-proposals` subdirectory.

### Bash Scripts (Recommended)

Located in `script/cancel-proposals/bash/`:

1. **list-pending-proposals.sh** - Lists all pending proposals in the timelock
2. **cancel-proposals.sh** - Generates Gnosis Safe transaction JSON files for cancelling proposals

These bash scripts are the recommended tools for emergency proposal cancellation. They:
- List all pending proposals
- Generate properly formatted JSON files for Gnosis Safe
- Allow for easy cancellation of malicious proposals

#### Usage

```bash
# List pending proposals
./script/cancel-proposals/bash/list-pending-proposals.sh

# Generate Gnosis Safe transaction JSON for cancelling a specific proposal
./script/cancel-proposals/bash/cancel-proposals.sh --proposal <proposal_id> --json

# Generate Gnosis Safe transactions for all pending proposals
./script/cancel-proposals/bash/cancel-proposals.sh --proposal all --json
```

See the dedicated README in `script/cancel-proposals/bash/` for detailed usage instructions.


## Other Scripts

- **TimelockRoleManager.s.sol** - Manages and verifies roles on the timelock controller
- **SetCancellers.s.sol** - Script to add addresses to the canceller role

## Emergency Cancellation Workflow

If a malicious proposal is discovered:

1. List pending proposals:
   ```bash
   ./script/cancel-proposals/bash/list-pending-proposals.sh
   ```

2. Generate cancellation transaction JSON file:
   ```bash
   ./script/cancel-proposals/bash/cancel-proposals.sh --proposal <proposal_id> --json
   ```

3. Import the generated JSON file into Gnosis Safe UI

4. Review and execute the transaction from the Foundation's L2 Safe

## Security Considerations

- Only addresses with the CANCELLER_ROLE can successfully execute cancel transactions
- The Foundation's L2 Safe must have been previously granted this role
- These tools do not execute transactions directly - they only generate the transaction data
- Always review the transaction in the Gnosis Safe UI before execution