---- Binary heap implementation
local BinaryHeap = {}
BinaryHeap.__index = BinaryHeap

function BinaryHeap:new()
    return setmetatable({items = {}, map = {}}, self)
end

function BinaryHeap:push(node)
    table.insert(self.items, node)
    --self.maxItemCount = math.max(#self.items,(self.maxItemCount or 0))
    self.map[node.y .. "_" .. node.x] = #self.items
    self:_bubbleUp(#self.items)
end

function BinaryHeap:pop()
    if #self.items == 0 then return nil end

    local root = self.items[1]
    local last = table.remove(self.items)

    if #self.items > 0 then
        self.items[1] = last
        self.map[last.y .. "_" .. last.x] = 1
        self:_bubbleDown(1)
    end

    self.map[root.y .. "_" .. root.x] = nil
    return root
end

function BinaryHeap:isEmpty()
    return #self.items == 0
end

function BinaryHeap:contains(node)
    return self.map[node.y .. "_" .. node.x] ~= nil
end

function BinaryHeap:update(node)
    local index = self.map[node.y .. "_" .. node.x]
    if index then
        self.items[index] = node
        self:_bubbleUp(index)
        self:_bubbleDown(index)
    end
end

function BinaryHeap:_bubbleUp(index)
    local item = self.items[index]
    while index > 1 do
        local parentIndex = math.floor(index / 2)
        local parent = self.items[parentIndex]
        if item.f_score >= parent.f_score then break end

        self.items[index] = parent
        self.map[parent.y .. "_" .. parent.x] = index
        index = parentIndex
    end
    self.items[index] = item
    self.map[item.y .. "_" .. item.x] = index
end

function BinaryHeap:_bubbleDown(index)
    local length = #self.items
    local item = self.items[index]

    while true do
        local leftChildIndex = 2 * index
        local rightChildIndex = 2 * index + 1
        local swapIndex = nil

        if leftChildIndex <= length then
            local leftChild = self.items[leftChildIndex]
            if leftChild.f_score < item.f_score then
                swapIndex = leftChildIndex
            end
        end

        if rightChildIndex <= length then
            local rightChild = self.items[rightChildIndex]
            if (swapIndex == nil and rightChild.f_score < item.f_score) or
               (swapIndex ~= nil and rightChild.f_score < self.items[swapIndex].f_score) then
                swapIndex = rightChildIndex
            end
        end

        if swapIndex == nil then break end

        self.items[index] = self.items[swapIndex]
        self.map[self.items[swapIndex].y .. "_" .. self.items[swapIndex].x] = index
        index = swapIndex
    end

    self.items[index] = item
    self.map[item.y .. "_" .. item.x] = index
end
return BinaryHeap
