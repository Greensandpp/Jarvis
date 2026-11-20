import assert from 'node:assert/strict';
import {buildRig,buildSnake,animateRig,animateSnake,THEMES} from '../assets/hologram/scene.js';
import * as THREE from '../assets/hologram/three.module.js';
const rig=buildRig(),snake=buildSnake();
assert.ok(rig.mesh.isSkinnedMesh);assert.ok(snake.mesh.isSkinnedMesh);
assert.ok(rig.bones.length>=36);assert.equal(snake.bones.length,32);
assert.deepEqual(Object.keys(THEMES),['snake','forest','solar','inferno','apex','mira']);
function positions(mesh){mesh.updateMatrixWorld(true);return mesh.skeleton.bones.map(b=>new THREE.Vector3().setFromMatrixPosition(b.matrixWorld).toArray());}
animateRig(rig,0,'idle');animateSnake(snake,0);const first=positions(rig.mesh),s1=positions(snake.mesh);
animateRig(rig,1.7,'listening');const second=positions(rig.mesh);
for(const name of ['head','elbowL','wristR','tipL2']){const i=rig.bones.indexOf(rig.named[name]);assert.notDeepEqual(first[i],second[i],name+' moves independently');}
assert.deepEqual(positions(snake.mesh),s1,'moving humanoid does not move serpent');
animateSnake(snake,2.6);assert.notDeepEqual(positions(snake.mesh),s1);assert.deepEqual(positions(rig.mesh),second,'moving serpent does not move humanoid');
animateRig(rig,3,'speaking',.8);assert.ok(rig.named.jaw.rotation.x>0);
animateRig(rig,3,'idle');assert.equal(rig.named.jaw.rotation.x,0);
animateRig(rig,1,'idle',0,0);assert.equal(rig.mesh.visible,false);
animateSnake(snake,1,.5);assert.equal(snake.mesh.visible,false);
animateRig(rig,1,'idle',0,.4);const assembly=rig.armour[0].position.clone();
animateRig(rig,1,'idle',0,1);assert.ok(assembly.distanceTo(rig.armour[0].position)>.2);
animateSnake(snake,1,1);assert.equal(snake.mesh.visible,true);
for(const mesh of [rig.mesh,snake.mesh]){
 const p=mesh.geometry.attributes.position,w=mesh.geometry.attributes.skinWeight,ix=mesh.geometry.attributes.skinIndex;
 for(let i=0;i<w.count;i++){assert.ok(Math.abs(w.getX(i)+w.getY(i)-1)<.0001);assert.ok(ix.getX(i)<mesh.skeleton.bones.length);}
 const v=new THREE.Vector3().fromBufferAttribute(p,Math.floor(p.count/2));const initial=v.clone();mesh.applyBoneTransform(Math.floor(p.count/2),v);assert.ok(Number.isFinite(v.x));assert.notDeepEqual(v.toArray(),initial.toArray(),'GPU skin data produces deformed vertices');
}
console.log('PASS: real skinned meshes; independent humanoid/serpent motion; joints/fingers/jaw; assembly visibility; six palettes; valid skin weights and bone deformation');
