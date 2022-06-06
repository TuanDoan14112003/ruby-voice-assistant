#1
import math
def democracy_sausage(menu, packsize, orders):
    
    #    2    
    ingredients = {item:0 for item in packsize.keys()}
    for cur_order in orders:
        order_ingredients = menu[cur_order]
        #    3   
        for cur_ingredient,cur_number in order_ingredients.items():
            ingredients[cur_ingredient] += cur_number
            
    packs = {}
    
    for cur_ingredient in ingredients:
        cur_number = ingredients[cur_ingredient]
        cur_size = packsize[cur_ingredient]
        cur_packs = cur_number // cur_size
        #    4    
        if cur_packs < math.ceil(cur_number / cur_size):
            cur_packs += 1
        packs[cur_ingredient] = cur_packs
    
    #    5
    return packs
menu = {
    'sausage in bread': {'bread': 1, 'sausage': 1}, 
    'sausage in bread with onion': {'bread': 1, 'sausage': 1, 'onion': 1},
    'bacon sandwich': {'bread': 2, 'bacon': 2},
    'bacon and egg sandwich': {'bread': 2, 'bacon': 2, 'egg': 1},
    'bacon and onion sandwich': {'bread': 2, 'bacon': 2, 'onion': 1}
}

packsize = {
    'sausage': 4,
    'bacon': 8,
    'egg': 6,
    'onion': 3,
    'bread': 10
}

orders = [
    'sausage in bread', 
    'sausage in bread with onion', 
    'sausage in bread', 
    'bacon sandwich', 
    'bacon and egg sandwich',
    'bacon and egg sandwich',
    'bacon sandwich',
    'bacon and onion sandwich',
    'sausage in bread',
    'sausage in bread'
]
# print(democracy_sausage(menu, packsize, orders))

if cur_packs < math.ceil(8 / 3):
    cur_packs += 1

print(cur_packs)