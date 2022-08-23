//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4 <0.9.0;
pragma abicoder v2;

import "../interfaces/IAggregator.sol";
import {BLSOpen} from  "./lib/BLSOpen.sol";
import "./IBLSWallet.sol";
import "./BLSHelper.sol";
import "hardhat/console.sol";

/**
 * A BLS-based signature aggregator, to validate aggregated signature of multiple UserOps if BLSWallet
 */
contract BLSSignatureAggregator is IAggregator {
    using UserOperationLib for UserOperation;

    bytes32 public constant BLS_DOMAIN = keccak256("eip4337.bls.domain");

    function validateSignatures(UserOperation[] calldata userOps, bytes calldata signature)
    external view override {
        require(signature.length == 64, "BLS: invalid signature");
        (uint256[2] memory blsSignature) = abi.decode(signature, (uint256[2]));

        uint userOpsLen = userOps.length;
        uint256[4][] memory blsPublicKeys = new uint256[4][](userOpsLen);
        uint256[2][] memory messages = new uint256[2][](userOpsLen);
        for (uint256 i = 0; i < userOpsLen; i++) {

            UserOperation memory userOp = userOps[i];
            IBLSWallet blsWallet = IBLSWallet(userOp.sender);

            blsPublicKeys[i] = blsWallet.getBlsPublicKey{gas : 30000}();

            messages[i] = _userOpToMessage(userOp, keccak256(abi.encode(blsPublicKeys[i])));
        }
        require(BLSOpen.verifyMultiple(blsSignature, blsPublicKeys, messages), "BLS: validateSignatures failed");
    }

    /**
     * get a hash of userOp
     * NOTE: this hash is not the same as UserOperation.hash()
     *  (slightly less efficient, since it uses memory userOp)
     */
    function getUserOpHash(UserOperation memory userOp) internal pure returns (bytes32) {
        return keccak256(abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                keccak256(userOp.paymasterAndData)
            ));
    }

    /**
     * return the BLS "message" for the given UserOp.
     * the wallet should sign this value using its public-key
     */
    function userOpToMessage(UserOperation memory userOp) public view returns (uint256[2] memory) {
        bytes32 hashPublicKey = _getUserOpPubkeyHash(userOp);
        return _userOpToMessage(userOp, hashPublicKey);
    }

    function _userOpToMessage(UserOperation memory userOp, bytes32 publicKeyHash) internal view returns (uint256[2] memory) {
        bytes32 requestId = _getRequestId(userOp, publicKeyHash);
        return BLSOpen.hashToPoint(BLS_DOMAIN, abi.encodePacked(requestId));
    }

    //return the public-key hash of a userOp.
    // if its a constructor UserOp, then return constructor hash.
    function _getUserOpPubkeyHash(UserOperation memory userOp) internal view returns (bytes32 hashPublicKey) {
        if (userOp.initCode.length == 0) {
            uint256[4] memory publicKey = IBLSWallet(userOp.sender).getBlsPublicKey();
            hashPublicKey = keccak256(abi.encode(publicKey));
        } else {
            hashPublicKey = keccak256(userOp.initCode);
        }
    }

    function getRequestId(UserOperation memory userOp) public view returns (bytes32) {
        bytes32 hashPublicKey = _getUserOpPubkeyHash(userOp);
        return _getRequestId(userOp, hashPublicKey);
    }

    function _getRequestId(UserOperation memory userOp, bytes32 hashPublicKey) internal view returns (bytes32) {
        return keccak256(abi.encode(getUserOpHash(userOp), hashPublicKey, address(this), block.chainid));
    }

    /**
     * validate signature of a single userOp
     * This method is called after EntryPoint.simulateUserOperation() returns an aggregator.
     * First it validates the signature over the userOp. then it return data to be used when creating the handleOps:
     * @param userOp the userOperation received from the user.
     * @return sigForUserOp the value to put into the signature field of the userOp when calling handleOps.
     *    (usually empty, unless wallet and aggregator support some kind of "multisig"
     * @return sigForAggregation the value to pass (for all wallets) to aggregateSignatures()
     * @return offChainSigInfo in case offChainSigCheck is true, return raw data to be validated off-chain.
     */
    function validateUserOpSignature(UserOperation calldata userOp, bool offChainSigCheck)
    external view returns (bytes memory sigForUserOp, bytes memory sigForAggregation, bytes memory offChainSigInfo) {
        uint256[2] memory signature = abi.decode(userOp.signature, (uint256[2]));
        uint256[4] memory pubkey = IBLSWallet(userOp.getSender()).getBlsPublicKey();
        uint256[2] memory message = userOpToMessage(userOp);

        if (offChainSigCheck) {
            offChainSigInfo = abi.encode(signature, pubkey, getRequestId(userOp));
        } else {
            require(BLSOpen.verifySingle(signature, pubkey, message), "BLS: wrong sig");
        }
        sigForUserOp = "";
        sigForAggregation = userOp.signature;
    }

    //copied from BLS.sol
    uint256 public  constant N = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /**
     * aggregate multiple signatures into a single value.
     * This method is called off-chain to calculate the signature to pass with handleOps()
     * bundler MAY use optimized custom code perform this aggregation
     * @param sigsForAggregation array of values returned by validateUserOpSignature() for each op
     * @return aggregatesSignature the aggregated signature
     */
    function aggregateSignatures(bytes[] memory sigsForAggregation) external pure returns (bytes memory aggregatesSignature) {
        BLSHelper.XY[] memory points = new BLSHelper.XY[](sigsForAggregation.length);
        for (uint i = 0; i < points.length; i++) {
            (uint x, uint y) = abi.decode(sigsForAggregation[i], (uint, uint));
            points[i] = BLSHelper.XY(x, y);
        }
        BLSHelper.XY memory sum = BLSHelper.sum(points, N);
        return abi.encode(sum.x, sum.y);
    }

}
