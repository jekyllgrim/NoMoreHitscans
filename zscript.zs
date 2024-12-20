version "4.14.0"

class NMH_HitscanHandler : EventHandler
{
	override bool WorldHitscanPreFired(WorldEvent e)
	{
		if (!nmh_enabled) return false;
		
		if (e.thing && e.thing.bIsMonster && !e.thing.player)
		{
			let proj = NMH_HitscanReplacer(e.thing.A_SpawnProjectile('NMH_HitscanReplacer',
				angle: e.AttackAngle - e.thing.angle,
				pitch: e.AttackPitch,
				flags: CMF_AIMDIRECTION));
			if (proj)
			{
				proj.nmh_damagefromhitscan = e.damage;
				proj.nmh_pufftype = Actor.GetReplacement(e.AttackPuffType);
				proj.damageType = e.damageType;
			}
			return true;
		}
		return false;
	}
}

class NMH_HitscanReplacer : Actor
{
	//int nmh_projstyle;
	int nmh_damagefromhitscan;
	class<Actor> nmh_pufftype;

	/*enum EProjStyles
	{
		PS_Tracer,
	}*/

	Default
	{
		+MISSILE
		+NOINTERACTION
		+FORCEXYBILLBOARD
		+BLOODSPLATTER
		Speed 80;
		RenderStyle 'Add';
		Height 0;
		Radius 0;
	}

	int GetProjDamage()
	{
		return nmh_damagefromhitscan;
	}

	void NMH_SpawnHitscanPuff()
	{
		let puff = Spawn(nmh_pufftype, pos, ALLOW_REPLACE);
		if (puff)
		{
			if (bHITTRACER) puff.tracer = tracer;
			if (bHITMASTER) puff.master = master;
			if (bHITTARGET || bPUFFGETSOWNER) puff.target = target;
		}
	}

	void HandleCollision()
	{
		let collision = NMH_ProjCollisionController.CheckCollision(self, self.pos, vel.Unit(), vel.Length());
		if (!collision) return;
		let hittype = collision.results.HitType;

		String report;
		switch (hittype)
		{
			case TRACE_HitActor:
				report = "actor";
				break;
			case TRACE_HitWall:
			case TRACE_HitFloor:
			case TRACE_HitCeiling:
				report = "geometry";
				break;
			case TRACE_HasHitSky:
				report = "sky";
				break;
			case Trace_HitNone:
				report = "nothing";
				break;
			default:
				report = "something else";
				break;
		}
		Console.Printf("Hit \cd"..report);

		if (hitType == TRACE_HitNone)
		{
			return;
		}

		A_Stop();
		if (hitType == TRACE_HitActor && collision.projectileVictim)
		{
			let vic = collision.projectileVictim;
			vic.DamageMobj(self, target? target : Actor(self), GetProjDamage(), damageType, DMG_INFLICTOR_IS_PUFF);
			if (!vic.bNOBLOOD && !vic.bDORMANT)
			{
				SetStateLabel("XDeath");
			}
			else
			{
				SetStateLabel("Death");
			}
			if (bHITTRACER) tracer = vic;
			if (bHITMASTER) master = vic;
			if (bHITTARGET) target = vic;
			return;
		}

		switch (hitType)
		{
		case TRACE_HitWall:
			if (collision.results.HitLine && target)
			{
				collision.results.HitLine.RemoteActivate(target, collision.results.Side, SPAC_Impact, pos);
			}
		case TRACE_HitCeiling:
		case TRACE_HitFloor:
			SetStateLabel("Death");
			break;
		case TRACE_HasHitSky:
			SetStateLabel("Null");
			break;
		}
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		vel = vel.Unit() * nmh_projspeed;
		A_FaceMovementDirection();
		HandleCollision();

		if (!nmh_pufftype) nmh_pufftype = 'BulletPuff';
		let puffdefs = GetDefaultByType(nmh_pufftype);
		bHITTRACER			= puffdefs.bHITTRACER;
		bHITMASTER			= puffdefs.bHITMASTER;
		bHITTARGET			= puffdefs.bHITTARGET;
		bPUFFGETSOWNER		= puffdefs.bPUFFGETSOWNER;
		bALLOWTHRUFLAGS		= puffdefs.bALLOWTHRUFLAGS;
		bTHRUSPECIES		= puffdefs.bTHRUSPECIES;
		bTHRUGHOST			= puffdefs.bTHRUGHOST;
		thruBits			= puffdefs.thruBits;
		species				= puffdefs.Species;
	}

	override void Tick()
	{
		Super.Tick();
		if (isFrozen() || !InStateSequence(curstate, spawnstate))
		{
			return;
		}

		HandleCollision();
	}

	States {
	Spawn:
		AMRK A -1 bright;
		stop;
	XDeath:
		TNT1 A 1
		{
			if (GetDefaultByType(nmh_pufftype).bPUFFONACTORS)
			{
				NMH_SpawnHitscanPuff();
			}
		}
		stop;
	Death:
		TNT1 A 1 NMH_SpawnHitscanPuff();
		stop;
	}
}

class NMH_ProjCollisionController : LineTracer
{
	Actor projectileSource;
	Actor projectileVictim;

	static NMH_ProjCollisionController CheckCollision(Actor source, Vector3 start, Vector3 direction, double range)
	{
		let tracer = new('NMH_ProjCollisionController');
		tracer.projectileSource = source;
		if (tracer.Trace(start, source.cursector, direction, range,
			TRACE_HitSky,
			wallmask: Line.ML_BLOCKEVERYTHING|Line.ML_BLOCKHITSCAN,
			ignore: source) == false)
		{
			return null;
		}
		return tracer;
	}

	override ETraceStatus TraceCallback()
	{
		if (results.HitType == TRACE_HitActor && results.HitActor)
		{
			let victim = results.HitActor;
			// hit its shooter:
			if (projectileSource.target == victim)
			{
				return TRACE_Skip;
			}
			// not shotable:
			if (!victim.bSolid && !victim.bShootable)
			{
				return TRACE_Skip;
			}
			// ghost:
			if (victim.bGHOST && projectileSource.bTHRUGHOST)
			{
				return TRACE_Skip;
			}
			// +ALLOWTHRUBITS and thrubits match:
			if (projectileSource.bALLOWTHRUBITS && (projectileSource.thruBits & victim.thruBits))
			{
				return TRACE_Skip;
			}
			// +ALLOWTHRUFLAGS +THRUSPECIES and species of projectile matches species of the victim:
			if (projectileSource.bALLOWTHRUFLAGS && projectileSource.bTHRUSPECIES && projectileSource.species == victim.species)
			{
				return TRACE_Skip;
			}
			// +MTHRUSPECIES and species of the projectile's shooter match species of the victim:
			if (projectileSource.target && projectileSource.bMTHRUSPECIES && projectileSource.target.species == victim.species)
			{
				return TRACE_Skip;
			}
			projectileVictim = victim;
			return TRACE_Stop;
		}

		switch (results.HitType)
		{
			case TRACE_HitWall:
			case TRACE_HitFloor:
			case TRACE_HitCeiling:
			case TRACE_HasHitSky:
				return TRACE_Stop;
				break;
		}

		return TRACE_Skip;
	}
}