import * as THREE from './three.module.js';
// Original GreenSoil armour sculpture: bevelled panels, curved shells, actual
// joint weights. No image assets. Consolidated into four GPU material groups.
export function buildGuardian(){
 const root=new THREE.Bone();root.name='pelvis';root.position.y=1.5;
 const bones=[root],named={pelvis:root},armour=[];
 const metal=new THREE.MeshStandardMaterial({color:0x677b89,metalness:.88,roughness:.27});
 const dark=new THREE.MeshStandardMaterial({color:0x08131e,metalness:.72,roughness:.4});
 const trim=new THREE.MeshStandardMaterial({color:0xd7a95e,metalness:.92,roughness:.25});
 const glow=new THREE.MeshStandardMaterial({color:0x59f4ff,emissive:0x25dfff,emissiveIntensity:2.4,metalness:.25,roughness:.18});
 const materials=[metal,dark,trim,glow];
 const add=(name,parent,pos)=>{const b=new THREE.Bone();b.name=name;b.position.set(...pos);parent.add(b);bones.push(b);named[name]=b;return b;};
 const chest=add('chest',root,[0,.52,0]),head=add('head',chest,[0,.72,0]);
 const jaw=add('jaw',head,[0,-.13,.13]),eyeL=add('eyeL',head,[-.085,.015,.182]),eyeR=add('eyeR',head,[.085,.015,.182]);
 for(const [s,side] of [[-1,'L'],[1,'R']]){
  const sh=add('shoulder'+side,chest,[s*.4,.32,0]),el=add('elbow'+side,sh,[s*.14,-.46,0]),wr=add('wrist'+side,el,[s*.045,-.39,.005]);
  for(let f=0;f<5;f++){const b=add('finger'+side+f,wr,[(f-2)*.039,-.12+Math.abs(f-2)*.014,.035]);add('tip'+side+f,b,[0,-(f===0?.067:.085),.005]);}
  const hip=add('hip'+side,root,[s*.185,-.1,0]),knee=add('knee'+side,hip,[s*.025,-.63,0]);add('ankle'+side,knee,[0,-.59,.015]);
 }
 for(const side of ['L','R'])named['finger'+side+'0'].rotation.z=side==='L'?-.75:.75;
 root.updateMatrixWorld(true);
 function part(b,g,pos=[0,0,0],mat=metal,scale=[1,1,1]){g.scale(...scale);g.translate(...pos);const m=new THREE.Mesh(g,mat);b.add(m);m.userData.rest=new THREE.Vector3();m.userData.bone=b;armour.push(m);return m;}
 const ell=(b,p,s,mat=metal)=>part(b,new THREE.SphereGeometry(1,20,12),p,mat,s);
 const tube=(b,p,r,h,mat=dark)=>part(b,new THREE.CapsuleGeometry(r,Math.max(.001,h-2*r),5,12),p,mat);
 function plate(b,outline,pos,depth=.035,mat=metal,bevel=.018){
  const shape=new THREE.Shape();outline.forEach(([x,y],i)=>i?shape.lineTo(x,y):shape.moveTo(x,y));shape.closePath();
  const g=new THREE.ExtrudeGeometry(shape,{depth,bevelEnabled:true,bevelSegments:3,steps:1,bevelSize:bevel,bevelThickness:bevel,curveSegments:8});
  const p=g.attributes.position;for(let i=0;i<p.count;i++)p.setZ(i,p.getZ(i)+Math.max(0,1-Math.abs(p.getX(i))/.55)*.022);g.computeVertexNormals();return part(b,g,pos,mat);
 }
 const shield=(w,h)=>[[-w*.85,h*.45],[-w,h*.1],[-w*.65,-h*.35],[0,-h*.55],[w*.65,-h*.35],[w,h*.1],[w*.85,h*.45],[0,h*.62]];
 const ring=(b,r,t,p,mat=trim)=>part(b,new THREE.TorusGeometry(r,t,8,40),p,mat);
 ell(root,[0,0,0],[.255,.18,.16],dark);ell(chest,[0,.16,0],[.355,.29,.19],dark);
 for(let i=0;i<4;i++){
  ell(head,[0,-.26+i*.025,0],[.078,.018,.078],i%2?trim:dark);
  const y=-.19-i*.075,w=.205-i*.02;plate(chest,[[-w,.02],[0,.04],[w,.02],[w*.8,-.035],[0,-.06],[-w*.8,-.035]],[0,y,.145],.015,i%2?metal:dark,.008);
 }
 for(const s of [-1,1]){
  plate(chest,[[s*.04,.35],[s*.19,.43],[s*.34,.32],[s*.32,.14],[s*.16,.05],[s*.045,.14]],[0,0,.125],.055);
  plate(chest,[[s*.045,.36],[s*.19,.445],[s*.34,.33],[s*.32,.305],[s*.18,.415]],[0,0,.19],.009,trim,.005);
  for(let i=0;i<3;i++)plate(chest,[[s*.19,0],[s*.31,.065],[s*.29,-.005],[s*.185,-.065]],[0,-i*.07,.12],.022,metal,.008);
  plate(root,[[s*.04,.08],[s*.24,.115],[s*.29,-.025],[s*.18,-.18],[s*.08,-.15]],[0,0,.12],.03);
  plate(root,[[s*.08,.07],[s*.22,.075],[s*.22,.055],[s*.09,.045]],[0,0,.168],.008,trim,.004);
 }
 plate(root,[[-.07,.03],[.07,.03],[.09,-.13],[0,-.24],[-.09,-.13]],[0,0,.16],.025,dark,.012);
 ring(chest,.106,.019,[0,.205,.225]);ring(chest,.077,.01,[0,.205,.245],dark);
 const reactor=ell(chest,[0,.205,.247],[.066,.066,.023],glow);
 for(let i=0;i<6;i++){const a=i*Math.PI/3;ell(chest,[Math.cos(a)*.128,.205+Math.sin(a)*.128,.216],[.011,.011,.012],glow);}
 ell(head,[0,.025,-.016],[.175,.235,.151],dark);ell(head,[0,.07,-.045],[.181,.215,.136]);
 plate(head,[[-.135,.145],[-.065,.205],[0,.15],[.065,.205],[.135,.145],[.11,.055],[0,.095],[-.11,.055]],[0,0,.117],.026);
 plate(head,[[-.035,.2],[0,.235],[.035,.2],[.022,.115],[0,.095],[-.022,.115]],[0,0,.149],.014,trim,.007);
 for(const s of [-1,1]){
  plate(head,[[s*.025,.065],[s*.135,.105],[s*.152,.025],[s*.122,-.105],[s*.055,-.15],[s*.035,-.045]],[0,0,.122],.025,metal,.012);
  plate(head,[[s*.042,-.02],[s*.13,.015],[s*.115,-.08],[s*.065,-.125]],[0,0,.167],.014,trim,.006);
  ell(head,[s*.177,.005,-.008],[.028,.083,.078],dark);ring(head,.044,.008,[s*.192,.015,.005]).rotation.y=Math.PI/2;
 }
 for(const [b,s] of [[eyeL,-1],[eyeR,1]])plate(b,[[-.049,.012],[.049,.007],[.04,-.014],[-.04,-.018]],[0,0,0],.012,glow,.004).rotation.z=-s*.12;
 plate(head,[[-.018,.015],[.018,.015],[.026,-.063],[0,-.085],[-.026,-.063]],[0,0,.166],.028,metal,.005);
 plate(jaw,[[-.078,.018],[-.03,-.015],[.03,-.015],[.078,.018],[.058,-.058],[0,-.095],[-.058,-.058]],[0,0,.03],.022,metal,.009);
 for(let i=0;i<3;i++)tube(jaw,[(i-1)*.023,-.036,.064],.003,.028,dark);
 for(const [s,side] of [[-1,'L'],[1,'R']]){
  const sh=named['shoulder'+side],el=named['elbow'+side],wr=named['wrist'+side],hip=named['hip'+side],kn=named['knee'+side],an=named['ankle'+side];
  ell(sh,[0,-.025,0],[.16,.17,.16],dark);ell(sh,[s*.015,.025,-.012],[.21,.155,.19]);plate(sh,shield(.165,.14),[s*.035,.05,.135],.034);
  plate(sh,[[s*-.1,.1],[s*.13,.1],[s*.17,.025],[s*-.12,.025]],[s*.02,0,.176],.009,trim,.006);
  tube(sh,[s*.065,-.23,0],.1,.34);ell(sh,[s*.04,-.24,.02],[.115,.2,.117]);plate(sh,shield(.08,.15),[s*.07,-.22,.11],.022);
  ell(el,[0,0,0],[.09,.09,.09],dark);ring(el,.065,.014,[0,0,.075]);tube(el,[s*.02,-.185,0],.09,.34);ell(el,[s*.01,-.19,.005],[.12,.19,.105]);
  plate(el,[[-.09,.14],[.075,.16],[.10,.015],[.06,-.17],[-.055,-.19],[-.105,.015]],[0,-.19,.085],.032);
  plate(el,[[s*-.035,.125],[s*.005,.13],[s*.045,-.13],[s*.025,-.15]],[0,-.19,.132],.009,glow,.004);
  for(let i=0;i<3;i++)ring(wr,.066-i*.003,.008,[0,.035-i*.018,0],i===1?trim:dark).rotation.x=Math.PI/2;
  ell(wr,[0,-.065,.003],[.087,.105,.055],dark);plate(wr,shield(.072,.065),[0,-.065,.047],.014);
  for(let f=0;f<5;f++){
   const fb=named['finger'+side+f],tip=named['tip'+side+f];tube(fb,[0,-.032,0],.017,.082,metal);ell(fb,[0,0,.004],[.019,.022,.019],dark);tube(tip,[0,-.031,0],.014,.075,metal);ell(tip,[0,-.065,.002],[.014,.017,.014],dark);ell(fb,[0,-.027,.019],[.01,.025,.004],trim);
  }
  tube(hip,[0,-.26,0],.115,.52);ell(hip,[0,-.24,.005],[.145,.29,.145]);plate(hip,[[-.105,.24],[.1,.22],[.12,.035],[.055,-.26],[-.045,-.27],[-.12,.01]],[0,-.26,.115],.035);
  plate(hip,[[s*-.09,.2],[s*-.055,.22],[s*.035,-.21],[s*.005,-.23]],[0,-.26,.17],.009,trim,.004);
  ell(kn,[0,0,0],[.096,.104,.105],dark);plate(kn,shield(.10,.105),[0,0,.1],.035);tube(kn,[0,-.27,0],.085,.53);ell(kn,[0,-.25,-.015],[.105,.26,.105]);
  plate(kn,[[-.08,.19],[.085,.19],[.105,.02],[.06,-.25],[0,-.29],[-.06,-.23],[-.095,.01]],[0,-.25,.075],.037);
  plate(kn,[[-.019,.14],[.018,.17],[.025,-.21],[0,-.25],[-.02,-.19]],[0,-.25,.13],.012,glow,.004);
  ell(an,[0,-.013,.065],[.115,.075,.22],dark);ell(an,[0,.018,.09],[.108,.06,.2]);for(let i=0;i<3;i++)ell(an,[0,.045-i*.008,.11+i*.04],[.095-i*.009,.025,.045],i===1?trim:metal);
 }
 const arrays={p:[],n:[],ix:[],w:[]},geometry=new THREE.BufferGeometry();let offset=0;
 for(let mi=0;mi<materials.length;mi++){
  const start=offset;
  for(const m of armour.filter(m=>m.material===materials[mi])){
   m.updateMatrix();const g=m.geometry.index?m.geometry.toNonIndexed():m.geometry.clone();g.applyMatrix4(m.matrix);g.applyMatrix4(m.userData.bone.matrixWorld);
   const p=g.attributes.position,n=g.attributes.normal,bi=bones.indexOf(m.userData.bone);
   for(let i=0;i<p.count;i++){arrays.p.push(p.getX(i),p.getY(i),p.getZ(i));arrays.n.push(n.getX(i),n.getY(i),n.getZ(i));arrays.ix.push(bi,0,0,0);arrays.w.push(1,0,0,0);}offset+=p.count;g.dispose();
  }geometry.addGroup(start,offset-start,mi);
 }
 geometry.setAttribute('position',new THREE.Float32BufferAttribute(arrays.p,3));geometry.setAttribute('normal',new THREE.Float32BufferAttribute(arrays.n,3));geometry.setAttribute('skinIndex',new THREE.Uint16BufferAttribute(arrays.ix,4));geometry.setAttribute('skinWeight',new THREE.Float32BufferAttribute(arrays.w,4));
 const mesh=new THREE.SkinnedMesh(geometry,materials);mesh.add(root);mesh.bind(new THREE.Skeleton(bones));mesh.frustumCulled=false;mesh.userData.asset='GreenSoil Guardian original armour v2';
 return {mesh,bones,named,armour,metal,dark,trim,glow,reactor,materials};
}
