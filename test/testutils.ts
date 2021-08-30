import {ethers} from "hardhat";
import {parseEther} from "ethers/lib/utils";
import {Contract, Wallet} from "ethers";
import {IERC20} from '../typechain'
import {BytesLike} from "@ethersproject/bytes";
import {
  SimpleWallet__factory
} from "../typechain";

export const AddressZero = ethers.constants.AddressZero
export const HashZero = ethers.constants.HashZero
export const ONE_ETH = parseEther('1');

export const tostr = (x: any) => x != null ? x.toString() : 'null'

export function tonumber(x: any): number {

  try {
    return parseFloat(x.toString())
  } catch (e) {
    console.log('=== failed to parseFloat:', x, e.message)
    return NaN
  }
}

//just throw 1eth from account[0] to the given address (or contract instance)
export async function fund(contractOrAddress: string | Contract) {
  let address: string
  if (typeof contractOrAddress == 'string') {
    address = contractOrAddress
  } else {
    address = contractOrAddress.address
  }
  await ethers.provider.getSigner().sendTransaction({to: address, value: parseEther('1')})
}

export async function getBalance(address: string): Promise<number> {
  const balance = await ethers.provider.getBalance(address)
  return parseInt(balance.toString())
}

export async function getTokenBalance(token: IERC20, address: string): Promise<number> {
  const balance = await token.balanceOf(address)
  return parseInt(balance.toString())
}


export function createWalletOwner(privkeyBase?: string): Wallet {
  const ran = ethers.Wallet.createRandom()
  return new ethers.Wallet(ran.privateKey, ethers.provider)
  // return new ethers.Wallet('0x'.padEnd(66, privkeyBase), ethers.provider);
}

export function WalletConstructor(singleton: string, owner: string): BytesLike {
  return new SimpleWallet__factory().getDeployTransaction(singleton, owner).data!
}

const panicCodes: { [key: string]: any } = {
  //from https://docs.soliditylang.org/en/v0.8.0/control-structures.html
  0x01: 'assert(false)',
  0x11: 'arithmetic overflow/underflow',
  0x12: 'divide by zero',
  0x21: 'invalid enum value',
  0x22: 'storage byte array that is incorrectly encoded',
  0x31: '.pop() on an empty array.',
  0x32: 'array sout-of-bounds or negative index',
  0x41: 'memory overflow',
  0x51: 'zero-initialized variable of internal function type'
}

//rethrow "cleaned up" exception.
// - stack trace goes back to method (or catch) line, not inner provider
// - attempt to parse revert data (needed for geth)
// use with ".catch(rethrow())", so that current source file/line is meaningful.
export function rethrow(): (e: Error) => void {
  let callerStack = new Error().stack!.replace(/Error.*\n.*at.*\n/, '').replace(/.*at.* \(internal[\s\S]*/, '')

  if ( arguments[0] ) {
    throw new Error( 'must use .catch(rethrow()), and NOT .catch(rethrow)')
  }
  return function (e: Error) {
    let solstack = e.stack!.match(/((?:.* at .*\.sol.*\n)+)/)
    let stack = (solstack != null ? solstack[1] : '') + callerStack
    // const regex = new RegExp('error=.*"data":"(.*?)"').compile()
    const found = /error=.*?"data":"(.*?)"/.exec(e.message)
    let message: string
    if (found != null) {
      const data = found![1]
      const methodSig = data.slice(0, 10)
      let dataParams = '0x' + data.slice(10);

      if (methodSig == '0x08c379a0') {
        const [err] = ethers.utils.defaultAbiCoder.decode(['string'], dataParams)
        message = `Error(${err})`
      } else if (methodSig == '0x00fa072b') {
        const [opindex, paymaster, msg] = ethers.utils.defaultAbiCoder.decode(['uint256', 'address', 'string'], dataParams)
        message = `FailedOp(${opindex}, ${paymaster != AddressZero ? paymaster : "none"}, ${msg})`
      } else if (methodSig == '0x4e487b71') {
        const [code] = ethers.utils.defaultAbiCoder.decode(['uint256'], dataParams)
        message = 'Panic(' + panicCodes[code] || code + ')'
      } else {
        message = e.message + ' - ' + data.slice(0, 100)
      }
    } else {
      message = e.message
    }
    const err = new Error(message)
    err.stack = 'Error: ' + message + '\n' + stack
    throw err
  }
}

let currentNode: string = ''

//basic geth support
// - by default, has a single account. our code needs more.
export async function checkForGeth() {
  // @ts-ignore
  const provider = ethers.provider._hardhatProvider

  currentNode = await provider.request({method: 'web3_clientVersion'})

  //NOTE: must run geth with params:
  // --http.api personal,eth,net,web3
  // --allow-insecure-unlock
  if (currentNode.match(/geth/i)) {
    for (let i = 0; i < 2; i++) {
      const acc = await provider.request({method: 'personal_newAccount', params: ['pass']}).catch(rethrow)
      await provider.request({method: 'personal_unlockAccount', params: [acc, 'pass']}).catch(rethrow)
      await fund(acc)
    }
  }
}


//remove "array" members, convert values to strings.
// so Result obj like
// { '0': "a", '1': 20, first: "a", second: 20 }
// becomes:
// { first: "a", second: "20" }
export function objdump(obj: { [key: string]: any }) {
  return Object.keys(obj)
    .filter(key => !key.match(/^[\d_]/))
    .reduce((set, key) => ({
      ...set,
      [key]: obj[key].toString()
    }), {})
}
