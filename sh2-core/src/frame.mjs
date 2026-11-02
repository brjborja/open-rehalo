// SmartHalo 2 — "bslink" link framing. See docs/protocol/ble-link.md §2-3.
// A message is <=80 B spread across 4 PAYLOAD characteristics of 20 B + 1 CTRL [len,crypted].
import { encrypt, decrypt } from './crypto.mjs';

export const MTU = 20;
export const PAYLOAD_CHARS = 4;
export const MAX_MESSAGE = MTU * PAYLOAD_CHARS; // 80

// Vendor service UUIDs (base 9254xxxx-d6ed-4617-a4b4-d749f57710ce).
const U = (x) => `9254${x}-d6ed-4617-a4b4-d749f57710ce`;
export const UUID = {
  service: U('0000'),
  ctrl: U('0001'),
  payload: [U('0010'), U('0011'), U('0012'), U('0013')],
  upCtrl: U('0101'),
  upPayload: [U('0110'), U('0111'), U('0112'), U('0113')],
};

/**
 * Encodes an application message to send to the device.
 * @param {Buffer} appData  plaintext payload (service,cmd,...args)
 * @param {{key?:Buffer, iv?:Buffer}} [cipher]  if given, encrypts the frame
 * @returns {{chunks:Buffer[], ctrl:Buffer}} chunks go to PAYLOAD[0..], then ctrl to CTRL
 */
export function encodeMessage(appData, cipher) {
  let body = appData;
  let crypted = 0;
  if (cipher && cipher.key) {
    body = encrypt(cipher.key, cipher.iv, appData);
    crypted = 1;
  }
  if (body.length > MAX_MESSAGE) {
    throw new Error(`message of ${body.length} B exceeds the maximum of ${MAX_MESSAGE}`);
  }
  const chunks = [];
  for (let i = 0; i < body.length; i += MTU) {
    chunks.push(body.subarray(i, Math.min(i + MTU, body.length)));
  }
  const ctrl = Buffer.from([body.length & 0xff, crypted]);
  return { chunks, ctrl };
}

/**
 * Decodes a reply (or UP notification) received from the device.
 * @param {Buffer} ctrl           CTRL value [len, crypted]
 * @param {Buffer} payloadAccum   concatenation of the notified PAYLOADs
 * @param {{key?:Buffer, iv?:Buffer}} [cipher]
 * @returns {Buffer} plaintext application payload
 */
export function decodeReply(ctrl, payloadAccum, cipher) {
  const len = ctrl[0];
  const crypted = ctrl[1];
  const body = payloadAccum.subarray(0, len);
  if (crypted) {
    if (!cipher || !cipher.key) throw new Error('encrypted frame but no key');
    return decrypt(cipher.key, cipher.iv, body);
  }
  return Buffer.from(body);
}
