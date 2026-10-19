import math

from odoo import http
from odoo.exceptions import AccessDenied
from odoo.http import request


class MupiMobilePosApiController(http.Controller):

    def _get_bearer_token(self):
        auth_header = request.httprequest.headers.get("Authorization")

        if not auth_header:
            return None

        parts = auth_header.split()

        if len(parts) != 2:
            return None

        if parts[0].lower() != "bearer":
            return None

        return parts[1]

    def _validate_mobile_token(self, required_scope=None):
        access_token = self._get_bearer_token()

        return request.env[
            "mupi.mobile.auth.token"
        ].sudo().validate_access_token(
            access_token,
            required_scope=required_scope,
        )

    def _auth_error_response(self, error):
        return {
            "ok": False,
            "error": error.args[0] if error.args else "Invalid token.",
        }
        
        
    def _format_product(self, product):
        return {
            "id": product.id,
            "name": product.display_name,
            "barcode": product.barcode or "",
            "default_code": product.default_code or "",
            "price": product.lst_price,
            "uom": product.uom_id.name if product.uom_id else "",
            #"image": product.image_128 or "",
            "stock_quantity": product.qty_available,
            "taxes": [
                {
                    "id": tax.id,
                    "name": tax.name,
                    "amount": tax.amount,
                    "amount_type": tax.amount_type,
                }
                for tax in product.taxes_id
            ],
            
            #"pos_categories": [
            #    {
            #        "id": category.id,
            #       "name": category.name,
            #   }
            #    for category in product.pos_categ_ids
            #],
            
            #"product_category": {
            #    "id": product.categ_id.id,
            #    "name": product.categ_id.name,
            #} if product.categ_id else False,
            
            "company_id": product.company_id.id if product.company_id else False,
            "active": product.active,
        }
        
    def _product_allowed_for_token(self, product, token_record):
        return not product.company_id or product.company_id == token_record.company_id
        
    def _create_product_audit(
        self,
        product,
        token_record,
        action,
        old_name=None,
        new_name=None,
        old_price=None,
        new_price=None,
        old_stock=None,
        new_stock=None,
    ):
        
        return False
    
        employee = token_record.employee_id
        
        return request.env["mupi.mobile.product.audit"].sudo().create({
            "product_id": product.id,
            "action": action,
            "old_name": old_name,
            "new_name": new_name,
            "old_price": old_price,
            "new_price": new_price,
            "old_stock": old_stock,
            "new_stock": new_stock,
            "user_id": token_record.user_id.id,
            "employee_id": employee.id or False,
            "pos_session_id": token_record.pos_session_id.id,
            "pos_config_id": token_record.pos_config_id.id,
            "company_id": token_record.company_id.id,
            "token_id": token_record.id,
        })
        
    @http.route(
        "/mupi/mobile/api/ping",
        type="json",
        auth="public",
        methods=["POST"],
        csrf=False,
    )
    def ping(self):
        try:
            token_record, payload = self._validate_mobile_token()
        except AccessDenied as error:
            return self._auth_error_response(error)

        return {
            "ok": True,
            "message": "Mobile POS API is available.",
            "token_id": token_record.id,
            "pos_session_id": token_record.pos_session_id.id,
            "pos_config_id": token_record.pos_config_id.id,
            "company_id": token_record.company_id.id,
        }
        
        
    @http.route(
        "/mupi/mobile/api/products/find",
        type="json",
        auth="public",
        methods=["POST"],
        csrf=False,
    )
    
    def find_product(self, barcode=None):
        try:
            token_record, payload = self._validate_mobile_token(
                required_scope="product:read",
            )
        except AccessDenied as error:
            return self._auth_error_response(error)

        if not barcode:
            return {
                "ok": False,
                "error": "Barcode is required.",
            }

        product = request.env["product.product"].sudo().search([
            ("barcode", "=", barcode),
            ("available_in_pos", "=", True),
            ("company_id", "in", [False, token_record.company_id.id]),
        ], limit=1)

        return {
            "ok": True,
            "product": self._format_product(product) if product else None,
        }
        
    @http.route(
        "/mupi/mobile/api/products/save",
        type="json",
        auth="public",
        methods=["POST"],
        csrf=False,
    )
    def save_product(
        self,
        barcode=None,
        name=None,
        price=None,
        tax_ids=None,
        pos_category_ids=None,
        product_category_id=None,
        image=None,
        default_code=None,
        create_only=False,
    ):
        try:
            token_record, payload = self._validate_mobile_token(
                required_scope="product:price_update",
            )
        except AccessDenied as error:
            return self._auth_error_response(error)

        if "product:name_update" not in (token_record.scopes or "").split():
            return {
                "ok": False,
                "error": "Token does not have required permission.",
            }

        if not name or not str(name).strip():
            return {
                "ok": False,
                "error": "Product name is required.",
            }
        
        if not barcode or not str(barcode).strip():
            return {
                "ok": False,
                "error": "Barcode is required.",
            }    

        try:
            price = float(price)
        except (TypeError, ValueError):
            return {
                "ok": False,
                "error": "Valid product price is required.",
            }

        if not math.isfinite(price) or price < 0:
            return {
                "ok": False,
                "error": "Price cannot be negative.",
            }

        Product = request.env["product.product"].sudo()

        # Serialize this endpoint's barcode writes, including legacy upserts.
        request.env.cr.execute(
            "SELECT pg_advisory_xact_lock(hashtext(%s))", [str(barcode)]
        )
        if create_only is True and Product.with_context(active_test=False).search_count([
            ("barcode", "=", barcode)
        ]):
            return {"ok": False, "error": "Barcode already exists."}
        if create_only is True:
            if not isinstance(tax_ids, list) or any(
                type(tax_id) is not int or tax_id <= 0 for tax_id in tax_ids
            ):
                return {"ok": False, "error": "Select valid product taxes."}
            allowed_taxes = request.env["account.tax"].sudo().search([
                ("id", "in", tax_ids),
                ("type_tax_use", "=", "sale"),
                ("active", "=", True),
                ("company_id", "=", token_record.company_id.id),
            ])
            if set(allowed_taxes.ids) != set(tax_ids):
                return {"ok": False, "error": "Select valid product taxes."}

        product = Product.browse()
        if barcode:
            product = Product.search([
                ("barcode", "=", barcode),
                ("company_id", "in", [False, token_record.company_id.id]),
            ], limit=1)

        values = {
            "name": str(name).strip(),
            "lst_price": price,
            "available_in_pos": True,
            "company_id": token_record.company_id.id,
        }

        if barcode:
            values["barcode"] = barcode

        if default_code:
            values["default_code"] = default_code

        #if image:
        #    values["image_1920"] = image

        #if product_category_id:
        #    values["categ_id"] = int(product_category_id)

        #if pos_category_ids:
        #    values["pos_categ_ids"] = [(6, 0, [int(category_id) for category_id in pos_category_ids])]

        if tax_ids or create_only is True:
            values["taxes_id"] = [(6, 0, [int(tax_id) for tax_id in tax_ids])]
        
        old_name = product.name if product else None
        old_price = product.lst_price if product else None
        old_stock = product.qty_available if product else None
        
        if product:
            if not self._product_allowed_for_token(product, token_record):
                return {
                    "ok": False,
                    "error": "Product is not allowed for this POS company.",
                }

            product.write(values)
            action = "updated"
        else:
            product = Product.create(values)
            action = "created"
            
        self._create_product_audit(
            product=product,
            token_record=token_record,
            action="product_update" if action == "updated" else "create",
            old_name=old_name,
            new_name=product.name,
            old_price=old_price,
            new_price=product.lst_price,
            old_stock=old_stock,
            new_stock=product.qty_available,
        )

        return {
            "ok": True,
            "message": "Product %s successfully." % action,
            "action": action,
            "product": self._format_product(product),
        }
        
    @http.route(
        "/mupi/mobile/api/products/price/update",
        type="json",
        auth="public",
        methods=["POST"],
        csrf=False,
    )
    def update_product_price(self, product_id=None, price=None):
        try:
            token_record, payload = self._validate_mobile_token(
                required_scope="product:price_update",
            )
        except AccessDenied as error:
            return self._auth_error_response(error)

        if not product_id:
            return {
                "ok": False,
                "error": "Product is required.",
            }

        try:
            product_id = int(product_id)
        except (TypeError, ValueError):
            return {
                "ok": False,
                "error": "Invalid product.",
            }

        product = request.env["product.product"].sudo().browse(product_id).exists()

        if not product:
            return {
                "ok": False,
                "error": "Product not found.",
            }

        if not self._product_allowed_for_token(product, token_record):
            return {
                "ok": False,
                "error": "Product is not allowed for this POS company.",
            }

        try:
            price = float(price)
        except (TypeError, ValueError):
            return {
                "ok": False,
                "error": "Invalid price.",
            }

        if price < 0:
            return {
                "ok": False,
                "error": "Price cannot be negative.",
            }
        
        old_price = product.lst_price
        old_stock = product.qty_available

        product.write({
            "lst_price": price,
        })
        
        self._create_product_audit(
            product=product,
            token_record=token_record,
            action="price_update",
            old_name=product.name,
            new_name=product.name,
            old_price=old_price,
            new_price=product.lst_price,
            old_stock=old_stock,
            new_stock=product.qty_available,
        )   

        return {
            "ok": True,
            "message": "Product price updated successfully.",
            "product": self._format_product(product),
        }
        
    
    @http.route(
    "/mupi/mobile/api/products/update",
    type="json",
    auth="public",
    methods=["POST"],
    csrf=False,
    )
    def update_product(self, product_id=None, name=None, tax_ids=None):
        try:
            token_record, payload = self._validate_mobile_token(
                required_scope="product:name_update",
            )
        except AccessDenied as error:
            return self._auth_error_response(error)

        if not product_id:
            return {
                "ok": False,
                "error": "Product is required.",
            }

        try:
            product_id = int(product_id)
        except (TypeError, ValueError):
            return {
                "ok": False,
                "error": "Invalid product.",
            }

        product = request.env["product.product"].sudo().browse(product_id).exists()

        if not product:
            return {
                "ok": False,
                "error": "Product not found.",
            }

        if not self._product_allowed_for_token(product, token_record):
            return {
                "ok": False,
                "error": "Product is not allowed for this POS company.",
            }

        if not name or not str(name).strip():
            return {
                "ok": False,
                "error": "Product name is required.",
            }

        values = {
            "name": str(name).strip(),
        }

        if tax_ids is not None:
            values["taxes_id"] = [(6, 0, [int(tax_id) for tax_id in tax_ids])]

        product.write(values)

        self._create_product_audit(
            product=product,
            token_record=token_record,
            action="product_update",
            old_name=False,
            new_name=product.name,
            old_price=product.lst_price,
            new_price=product.lst_price,
            old_stock=product.qty_available,
            new_stock=product.qty_available,
        )

        return {
            "ok": True,
            "message": "Product updated successfully.",
            "product": self._format_product(product),
        }   

   
    @http.route(
    "/mupi/mobile/api/products/references",
    type="json",
    auth="public",
    methods=["POST"],
    csrf=False,
    )
    def product_references(self):
        try:
            token_record, payload = self._validate_mobile_token(
            required_scope="reference:read",
        )
        except AccessDenied as error:
            return self._auth_error_response(error)

        company = token_record.company_id

        taxes = request.env["account.tax"].sudo().search([
            ("type_tax_use", "=", "sale"),
            ("active", "=", True),
            ("company_id", "=", company.id),
        ])

        #pos_categories = request.env["pos.category"].sudo().search([])
        #product_categories = request.env["product.category"].sudo().search([])

        default_values = (
            request.env["product.template"]
            .sudo()
            .with_company(company)
            .default_get(["taxes_id"])
        )

        default_tax_ids = [
            tax_id
            for tax_id in default_values.get("taxes_id", [])
            if tax_id in taxes.ids
        ]

        return {
            "ok": True,
            "default_tax_ids": default_tax_ids,
            "create_only_supported": True,
            "taxes": [
                {
                    "id": tax.id,
                    "name": tax.name,
                    "amount": tax.amount,
                    "amount_type": tax.amount_type,
                }
                for tax in taxes
            ],
            
            #"pos_categories": [
            #    {"id": category.id, "name": category.display_name}
            #    for category in pos_categories
            #],
            
            #"product_categories": [
            #    {"id": category.id, "name": category.display_name}
            #    for category in product_categories
            #],
        }
   
   
    @http.route(
        "/mupi/mobile/api/products/name/update",
        type="json",
        auth="public",
        methods=["POST"],
        csrf=False,
    )
    def update_product_name(self, product_id=None, name=None):
        try:
            token_record, payload = self._validate_mobile_token(
                required_scope="product:name_update",
            )
        except AccessDenied as error:
            return self._auth_error_response(error)

        if not product_id:
            return {
                "ok": False,
                "error": "Product is required.",
            }

        try:
            product_id = int(product_id)
        except (TypeError, ValueError):
            return {
                "ok": False,
                "error": "Invalid product.",
            }

        product = request.env["product.product"].sudo().browse(product_id).exists()

        if not product:
            return {
                "ok": False,
                "error": "Product not found.",
            }

        if not self._product_allowed_for_token(product, token_record):
            return {
                "ok": False,
                "error": "Product is not allowed for this POS company.",
            }

        if not name or not str(name).strip():
            return {
                "ok": False,
                "error": "Product name is required.",
            }
        
        old_name = product.name
        old_price = product.lst_price
        old_stock = product.qty_available

        product.write({
            "name": str(name).strip(),
        })
        
        self._create_product_audit(
            product=product,
            token_record=token_record,
            action="product_update",
            old_name=old_name,
            new_name=product.name,
            old_price=old_price,
            new_price=product.lst_price,
            old_stock=old_stock,
            new_stock=product.qty_available,
        )

        return {
            "ok": True,
            "message": "Product name updated successfully.",
            "product": self._format_product(product),
        }
