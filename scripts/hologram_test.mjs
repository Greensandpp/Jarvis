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
const spine=positions(snake.mesh);assert.ok(Math.max(...spine.map(p=>p[1]))>2.5);assert.ok(Math.min(...spine.map(p=>p[1]))<.6);assert.ok(spine.some(p=>p[2]>.6)&&spine.some(p=>p[2]<-.6),'serpent coils in front and behind the torso');
for(const mesh of [rig.mesh,snake.mesh]){
 const p=mesh.geometry.attributes.position,w=mesh.geometry.attributes.skinWeight,ix=mesh.geometry.attributes.skinIndex;
 for(let i=0;i<w.count;i++){assert.ok(Math.abs(w.getX(i)+w.getY(i)-1)<.0001);assert.ok(ix.getX(i)<mesh.skeleton.bones.length);}
 const v=new THREE.Vector3().fromBufferAttribute(p,Math.floor(p.count/2));const initial=v.clone();mesh.applyBoneTransform(Math.floor(p.count/2),v);assert.ok(Number.isFinite(v.x));assert.notDeepEqual(v.toArray(),initial.toArray(),'GPU skin data produces deformed vertices');
}
console.log('PASS: real skinned meshes; independent humanoid/serpent motion; joints/fingers/jaw; assembly visibility; six palettes; valid skin weights and bone deformation');
assert.equal(rig.materials.length,4);assert.equal(rig.mesh.geometry.groups.length,4);
assert.ok(rig.armour.length>150);assert.ok(rig.armour.every(m=>m.geometry.type!=='BoxGeometry'),'no block armour');
assert.ok(rig.mesh.geometry.attributes.position.count>15000);assert.ok(snake.mesh.geometry.attributes.position.count>2500);
for(let t=0;t<15;t+=.25){animateSnake(snake,t);assert.ok(snake.head.getWorldPosition(new THREE.Vector3()).x>.60,'helmet clearance');}
const {QUALITY,introStage}=await import('../assets/hologram/scene.js');
assert.deepEqual(Object.keys(QUALITY),['ultra','high','balanced','battery']);assert.equal(QUALITY.battery.fps,30);
assert.deepEqual([0,.1,.2,.4,.65,.73,.8,.95,1].map(introStage),['platform','convergence','skeleton','armour','reactor','eyes','serpent','approach','idle']);
console.log(`PASS: detailed original guardian (${rig.armour.length} pieces, ${rig.mesh.geometry.attributes.position.count/3} triangles), four consolidated groups, organic snake/face clearance, quality and intro stages`);

// Actual animated geometry must fit both tall Android viewports and wider screens.
const {portraitCameraDistance}=await import('../assets/hologram/scene.js');
for(const aspect of [.30,.34,.40,.45,.50,.60,.75,1,2]) {
 const camera=new THREE.PerspectiveCamera(36,aspect,.1,60);
 const d=portraitCameraDistance(6.7,aspect);
 camera.position.set(0,2+.06*d,d);camera.lookAt(0,1.7,0);camera.updateMatrixWorld(true);
 for(let t=0;t<30;t+=.125) {
  animateSnake(snake,t,1);snake.mesh.updateMatrixWorld(true);snake.head.updateMatrixWorld(true);
  const box=new THREE.Box3().setFromObject(snake.head,true);
  for(const x of [box.min.x,box.max.x])for(const y of [box.min.y,box.max.y])for(const z of [box.min.z,box.max.z]) {
   const p=new THREE.Vector3(x,y,z).project(camera);
   assert.ok(Math.abs(p.x)<1&&Math.abs(p.y)<1,`animated head clipped: aspect=${aspect} t=${t} x=${p.x} y=${p.y}`);
  }
 }
}
console.log('PASS: full animated serpent head stays inside 9 viewport aspects over 30 seconds');
