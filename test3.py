def can_deliver(offices, power):
    delivery_order = sorted(offices)
    # print(delivery_order)
    prev_floor = 1
    for delivery_loc in delivery_order:
        
        if power <= 0:
            return False
        flooroffice = delivery_loc.split('-')
        floor = int(flooroffice[0])
        office = int(flooroffice[1])
        if floor == prev_floor:
            power -= 1
        else:
            power -= 2 * abs(floor - prev_floor)
            prev_floor = floor
        # print('floor is', floor)
        # print(power)
    
    return True
can_deliver(['1-2','1-3','1-4'],5)
can_deliver(['1-3','10-4','20-3'],4)
can_deliver(['1-2','5-9'],4)
can_deliver(['1-1'],0)