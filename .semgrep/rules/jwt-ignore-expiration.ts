// Test cases for jwt-ignore-expiration.
/* eslint-disable */

async function check(jwtService: any, token: string) {
  // ruleid: jwt-ignore-expiration
  await jwtService.verifyAsync(token, { ignoreExpiration: true });

  // ok: jwt-ignore-expiration
  await jwtService.verifyAsync(token);
}
