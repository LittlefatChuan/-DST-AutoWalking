function StepToVector3(step)
	return Vector3(step.x, step.y, step.z)
end

function Vector3ToStep(point)
	return {y = point.y, x = point.x, z = point.z}
end