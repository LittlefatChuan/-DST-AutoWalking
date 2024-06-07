function StepToVector3(step)
	return Vector3(step.x, step.y, step.z)
end

function Vector3ToStep(point)
	return {y = point.y, x = point.x, z = point.z}
end

-- 有效的路径，至少要有两个step，起点和终点
function IsValidPath(path)
	return path ~= nil and path.steps and #path.steps >= 2
end